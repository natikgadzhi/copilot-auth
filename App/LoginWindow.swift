import AppKit
import CopilotAuthKit
import SwiftUI
import WebKit

/// Hosts the auth manager's login web view in SwiftUI.
struct LoginWebView: NSViewRepresentable {
  let webView: WKWebView

  func makeNSView(context: Context) -> WKWebView {
    // Labels for VoiceOver and for agents driving the app via the Accessibility
    // API (the web content itself is exposed by WKWebView automatically).
    webView.setAccessibilityLabel("Copilot sign-in web page")
    webView.setAccessibilityIdentifier("copilotLoginWebView")
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {}
}

@MainActor
struct LoginWindowContent: View {
  let manager: CopilotAuthManager
  let onAuthenticated: () -> Void

  @State private var link = ""
  @State private var pendingLink: URL?
  @State private var confirmingUntrustedHost = false

  var body: some View {
    VStack(spacing: 0) {
      LoginWebView(webView: manager.loginWebView)
        .frame(minWidth: 480, minHeight: 640)

      // The paste field only matters once Copilot has emailed the sign-in link,
      // so it stays hidden until that screen appears.
      if manager.signInLinkSent {
        Divider()
        pasteBar
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.snappy, value: manager.signInLinkSent)
    .onChange(of: manager.state) { _, newValue in
      if newValue == .authenticated { onAuthenticated() }
    }
    .confirmationDialog(
      "Open this sign-in link?", isPresented: $confirmingUntrustedHost, presenting: pendingLink
    ) { url in
      Button("Open \(url.host ?? "link")") { manager.loadSignInLink(url) }
      Button("Cancel", role: .cancel) {}
    } message: { url in
      Text(
        "It will load \(url.host ?? url.absoluteString) in this window. "
          + "Only open links from Copilot's sign-in email.")
    }
  }

  /// Footer affordance for Copilot's passwordless flow: the email's sign-in link
  /// opens in the system browser, not here, so the user pastes it back (⌘V) to
  /// finish. Shown only once Copilot reports the link was sent.
  private var pasteBar: some View {
    VStack(alignment: .leading) {
      Text("Check your email, then paste the sign-in link here to finish (⌘V).")
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("pasteInstructions")

      HStack {
        TextField("https://…", text: $link)
          .textFieldStyle(.roundedBorder)
          .onSubmit(open)
          .accessibilityLabel("Sign-in link")
          .accessibilityHint("Paste the sign-in link from your Copilot email")
          .accessibilityIdentifier("signInLinkField")

        Button("Open", action: open)
          .buttonStyle(.borderedProminent)
          .disabled(parsedLink == nil)
          .accessibilityLabel("Open sign-in link")
          .accessibilityHint("Loads the pasted link to finish signing in")
          .accessibilityIdentifier("openSignInLinkButton")
      }

      if let url = parsedLink {
        let trusted = CopilotEndpoint.isTrustedSignInHost(url)
        Label(
          "Opens \(url.host ?? url.absoluteString)",
          systemImage: trusted ? "lock.fill" : "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(trusted ? Color.secondary : Color.orange)
        .accessibilityIdentifier("destinationHost")
      }
    }
    .padding()
  }

  /// The trimmed pasted text as an `https` URL, or nil if it isn't one.
  private var parsedLink: URL? {
    guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme == "https"
    else {
      return nil
    }
    return url
  }

  /// Load a trusted Copilot/Firebase host straight away; confirm anything else
  /// first, since the link loads into the web view that holds the session.
  private func open() {
    guard let url = parsedLink else { return }
    if CopilotEndpoint.isTrustedSignInHost(url) {
      manager.loadSignInLink(url)
    } else {
      pendingLink = url
      confirmingUntrustedHost = true
    }
  }
}
