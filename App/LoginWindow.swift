import AppKit
import CopilotAuthKit
import SwiftUI
import WebKit

/// Hosts the auth manager's login web view in SwiftUI.
struct LoginWebView: NSViewRepresentable {
  let webView: WKWebView
  func makeNSView(context: Context) -> WKWebView { webView }
  func updateNSView(_ nsView: WKWebView, context: Context) {}
}

@MainActor
struct LoginWindowContent: View {
  let manager: CopilotAuthManager
  let onAuthenticated: () -> Void
  @State private var link = ""

  var body: some View {
    VStack(spacing: 0) {
      LoginWebView(webView: manager.loginWebView)
        .frame(minWidth: 480, minHeight: 640)
      Divider()
      // Copilot's passwordless login emails a one-time link that opens in the
      // system browser, not here. Paste it back so it completes in this web view.
      HStack(spacing: 8) {
        TextField("Paste the sign-in link from your email…", text: $link)
          .textFieldStyle(.roundedBorder)
          .onSubmit(open)
        Button("Paste") {
          link = NSPasteboard.general.string(forType: .string) ?? link
        }
        Button("Open", action: open)
          .keyboardShortcut(.defaultAction)
          .disabled(parsedLink == nil)
      }
      .padding(8)
    }
    .onChange(of: manager.state) { _, newValue in
      if newValue == .authenticated { onAuthenticated() }
    }
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

  private func open() {
    guard let url = parsedLink else { return }
    manager.loadSignInLink(url)
  }
}
