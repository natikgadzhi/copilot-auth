import AppKit

/// The app's About panel — the GUI equivalent of the CLI's `--help` overview.
///
/// Uses the standard macOS About panel (icon + name + version) enriched via its
/// credits field with a one-line summary and links to this repo and the
/// companion CLI it feeds.
enum About {
  private static let summary = """
    Sign in to Copilot Money in a web view and store the tokens the copilot.py \
    CLI needs — in your Keychain, on your own machine.
    """
  private static let repo = URL(string: "https://github.com/natikgadzhi/copilot-auth")!
  private static let companion = URL(string: "https://github.com/natikgadzhi/copilot-python")!

  static func showPanel() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits()])
  }

  private static func credits() -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.paragraphSpacing = 8
    let base: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
      .foregroundColor: NSColor.secondaryLabelColor,
      .paragraphStyle: style,
    ]
    let text = NSMutableAttributedString(string: summary + "\n\n", attributes: base)
    text.append(linkRun("View source on GitHub", repo, base))
    text.append(NSAttributedString(string: "\n", attributes: base))
    text.append(NSAttributedString(string: "Companion CLI: ", attributes: base))
    text.append(linkRun("copilot-python", companion, base))
    return text
  }

  private static func linkRun(
    _ text: String, _ url: URL, _ base: [NSAttributedString.Key: Any]
  ) -> NSAttributedString {
    var attrs = base
    attrs[.link] = url
    return NSAttributedString(string: text, attributes: attrs)
  }
}
