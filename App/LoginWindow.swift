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
  @FocusState private var linkFieldFocused: Bool

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
    VStack(alignment: .leading, spacing: 10) {
      Text("Check your email, then paste the sign-in link here to finish (⌘V).")
        .font(.system(size: 13))
        .foregroundStyle(CopilotStyle.ink.opacity(0.6))
        .accessibilityIdentifier("pasteInstructions")

      HStack(spacing: 10) {
        linkField
        Button("Open", action: open)
          .buttonStyle(CopilotPrimaryButtonStyle())
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
        .foregroundStyle(trusted ? CopilotStyle.ink.opacity(0.55) : Color.orange)
        .accessibilityIdentifier("destinationHost")
      }
    }
    // Uniform breathing room on the sides and bottom (a touch less up top, since
    // the divider already separates it from the web view).
    .padding(.horizontal, 18)
    .padding(.top, 14)
    .padding(.bottom, 18)
    .background(CopilotStyle.surface)
  }

  /// A text field dressed to match Copilot's web input: slate fill, hairline
  /// border, 12pt rounded, and an accent focus ring.
  private var linkField: some View {
    TextField("https://…", text: $link)
      .textFieldStyle(.plain)
      .focused($linkFieldFocused)
      .focusEffectDisabled()
      .font(.system(size: CopilotStyle.fieldFontSize))
      .foregroundStyle(CopilotStyle.ink)
      .padding(.horizontal, 12)
      .frame(height: CopilotStyle.controlHeight)
      .background(
        CopilotStyle.fieldFill, in: RoundedRectangle(cornerRadius: CopilotStyle.cornerRadius)
      )
      .overlay {
        RoundedRectangle(cornerRadius: CopilotStyle.cornerRadius)
          .strokeBorder(
            linkFieldFocused ? CopilotStyle.accent : CopilotStyle.fieldStroke,
            lineWidth: linkFieldFocused ? 1 : 0.5)
      }
      .shadow(color: linkFieldFocused ? CopilotStyle.accent.opacity(0.22) : .clear, radius: 3)
      .animation(.easeOut(duration: 0.12), value: linkFieldFocused)
      .onSubmit(open)
      .accessibilityLabel("Sign-in link")
      .accessibilityHint("Paste the sign-in link from your Copilot email")
      .accessibilityIdentifier("signInLinkField")
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
