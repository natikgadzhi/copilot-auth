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

  /// True once Copilot shows its "we've sent a sign-in link" screen — the cue to
  /// reveal the paste-the-link field. Stays true thereafter (resends are fine).
  public private(set) var signInLinkSent = false

  private var webView: WKWebView?
  private var captureTask: Task<Void, Never>?

  /// How often the capture poll re-reads IndexedDB while waiting for login.
  private let pollInterval: Duration = .seconds(1.5)

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
    // Inspectable in debug only: a distributed release must not expose the logged
    // in session's IndexedDB (the raw refresh token) to Safari's Web Inspector.
    // `make authenticate` builds Debug, so local verification keeps the inspector.
    #if DEBUG
      webView.isInspectable = true
    #endif
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
    startCapturePolling()
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
    startCapturePolling()
  }

  /// Poll the page's IndexedDB until the Firebase secrets appear. Firebase writes
  /// them asynchronously after login — sometimes with no further navigation — so a
  /// single read on `didCommit` misses them; we re-read on an interval instead.
  private func startCapturePolling() {
    guard captureTask == nil else { return }
    captureTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self, self.state != .authenticated else { return }
        await self.attemptCapture()
        if self.state == .authenticated { return }
        try? await Task.sleep(for: self.pollInterval)
      }
    }
  }

  /// One capture attempt: run the read JS, persist on success, log a secret-free
  /// diagnostic on a miss so failures are debuggable.
  private func attemptCapture() async {
    guard let webView else { return }
    do {
      let result = try await webView.callAsyncJavaScript(
        CopilotCapture.indexedDBReadJS, arguments: [:], contentWorld: .page)
      if let captured = CopilotCapture.parse(result) {
        ingest(captured: captured)
      } else {
        log.info("capture miss: \(CopilotCapture.diagnostic(result), privacy: .public)")
        if !signInLinkSent { await detectSignInPrompt(in: webView) }
      }
    } catch {
      log.error("capture error: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Reveal the paste-the-link field only once Copilot shows its "we've sent a
  /// sign-in link" screen, so the field isn't clutter the rest of the time.
  private func detectSignInPrompt(in webView: WKWebView) async {
    guard let result = try? await webView.evaluateJavaScript(CopilotCapture.signInPromptJS),
      let shown = result as? Bool, shown
    else {
      return
    }
    log.info("sign-in prompt detected — revealing the paste field")
    signInLinkSent = true
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
    captureTask?.cancel()
    captureTask = nil
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
    captureTask?.cancel()
    captureTask = nil
    secretStore.clear()
    secrets = nil
    signInLinkSent = false
    state = .unauthenticated
  }
}

extension CopilotAuthManager: WKNavigationDelegate {
  public func webView(
    _ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!
  ) {
    log.info("didStart: \(webView.url?.host ?? "<nil>", privacy: .public)")
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
    log.info("didFinish: \(webView.url?.host ?? "<nil>", privacy: .public)")
  }

  /// The web content process crashing is the classic "blank page" cause — log it
  /// loudly so we can tell it apart from a network/navigation failure.
  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    log.error("webContentProcessDidTerminate — WKWebView render process died")
  }

  /// Capture runs on a poll (see `startCapturePolling`), not here: the Firebase
  /// record is written asynchronously after login, often with no further commit.
  public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    log.info("didCommit: \(webView.url?.host ?? "<nil>", privacy: .public)")
  }
}
