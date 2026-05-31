import SwiftUI

/// Visual constants read from Copilot's web sign-in page (app.copilot.money) so
/// the native paste bar matches the web view above it. Explicit light colors on
/// purpose: the Copilot UI is light-only and the bar sits beneath its white page.
enum CopilotStyle {
  /// #437CEF — the Copilot accent (button fill + focus ring).
  static let accent = Color(red: 67 / 255, green: 124 / 255, blue: 239 / 255)
  /// #143352 — Copilot's ink/navy text.
  static let ink = Color(red: 20 / 255, green: 51 / 255, blue: 82 / 255)
  /// Slate at 8% — the input fill.
  static let fieldFill = Color(red: 139 / 255, green: 149 / 255, blue: 172 / 255).opacity(0.08)
  /// Near-black at 8% — the input's hairline border.
  static let fieldStroke = Color(red: 10 / 255, green: 14 / 255, blue: 20 / 255).opacity(0.08)
  /// The white surface the controls sit on, matching the web view.
  static let surface = Color.white

  static let cornerRadius: CGFloat = 12
  static let controlHeight: CGFloat = 44
  static let fieldFontSize: CGFloat = 16
}
