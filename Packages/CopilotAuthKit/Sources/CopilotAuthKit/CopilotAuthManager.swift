import Foundation
import Observation
import WebKit
import os

/// Coordinates the interactive login: owns the `WKWebView` the user signs into,
/// and snapshots the Firebase secrets once they appear in the page's IndexedDB.
///
/// Why a real WebView instead of scripted HTTP: Copilot's login is a JS-rendered
/// Firebase flow (email/password + 2FA), so we let a genuine browser do the dance
/// and read the resulting refresh token out of `firebaseLocalStorageDb`.
@MainActor @Observable
public final class CopilotAuthManager: NSObject {
  private let secretStore: any CopilotSecretStoring
  private let log = Logger(subsystem: "io.respawn.copilot", category: "auth")

  public private(set) var state: AuthenticationState = .new
  public private(set) var secrets: CopilotSessionSecrets?

  private var webView: WKWebView?

  public init(secretStore: any CopilotSecretStoring) {
    self.secretStore = secretStore
    super.init()
  }

  /// The login web view; the caller embeds this in a window. Uses the default
  /// (persistent) data store on purpose so Copilot's "remember this device" can
  /// reduce repeat 2FA prompts.
  public var loginWebView: WKWebView {
    if let webView { return webView }
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.navigationDelegate = self
    webView.isInspectable = true
    self.webView = webView
    return webView
  }

  /// Start login by loading the Copilot app; it redirects to sign-in if the user
  /// isn't authenticated yet.
  public func startLogin() {
    let url = CopilotEndpoint.app.url
    log.info("startLogin: loading \(url.absoluteString, privacy: .public)")
    state = .authenticating
    loginWebView.load(URLRequest(url: url))
  }

  /// Load a pasted email sign-in link in the *same* web view. Copilot's
  /// passwordless login emails a one-time link that would otherwise open in the
  /// system browser; loading it here completes Firebase's `signInWithEmailLink`
  /// in the context where the user entered their email (it's in this web view's
  /// localStorage), so capture proceeds as usual.
  ///
  /// The URL carries a one-time `oobCode`, so we log only the host — never the
  /// full link.
  public func loadSignInLink(_ url: URL) {
    log.info("loadSignInLink: host=\(url.host ?? "<nil>", privacy: .public)")
    state = .authenticating
    loginWebView.load(URLRequest(url: url))
  }

  /// Single capture point — persists only when both secrets are present. Pure
  /// (no WebView), so it's unit-testable.
  public func ingest(captured: CapturedSecrets?) {
    guard let captured else { return }
    let secrets = CopilotSessionSecrets(
      refreshToken: captured.refreshToken, apiKey: captured.apiKey)
    secretStore.write(secrets: secrets)
    self.secrets = secrets
    state = .authenticated
  }

  public func initSessionFromSecureStorage() {
    guard let stored = secretStore.read() else {
      state = .unauthenticated
      return
    }
    secrets = stored
    state = .authenticated
  }

  public func reset() {
    secretStore.clear()
    secrets = nil
    state = .unauthenticated
  }
}

extension CopilotAuthManager: WKNavigationDelegate {
  public func webView(
    _ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!
  ) {
    log.info("didStart: \(webView.url?.absoluteString ?? "<nil>", privacy: .public)")
  }

  public func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    log.error("didFailProvisional: \(error.localizedDescription, privacy: .public)")
  }

  public func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
  ) {
    log.error("didFail: \(error.localizedDescription, privacy: .public)")
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    log.info("didFinish: \(webView.url?.absoluteString ?? "<nil>", privacy: .public)")
  }

  /// The web content process crashing is the classic "blank page" cause — log it
  /// loudly so we can tell it apart from a network/navigation failure.
  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    log.error("webContentProcessDidTerminate — WKWebView render process died")
  }

  /// After each navigation commit, read the Firebase IndexedDB record; `ingest`
  /// no-ops until both secrets have landed (post-login), then persists once.
  public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    log.info("didCommit: \(webView.url?.absoluteString ?? "<nil>", privacy: .public)")
    guard state != .authenticated else { return }
    Task { @MainActor in
      let result = try? await webView.callAsyncJavaScript(
        CopilotCapture.indexedDBReadJS, arguments: [:], contentWorld: .page)
      ingest(captured: CopilotCapture.parse(result))
    }
  }
}
