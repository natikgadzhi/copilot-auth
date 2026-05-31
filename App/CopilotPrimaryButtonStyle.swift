import SwiftUI

/// Copilot's "Continue" button look: solid accent fill, white semibold text,
/// 12pt rounded, dimmed when disabled the way Copilot's is.
struct CopilotPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PrimaryButtonLabel(configuration: configuration)
  }

  private struct PrimaryButtonLabel: View {
    let configuration: Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(height: CopilotStyle.controlHeight)
        .padding(.horizontal, 18)
        .background(
          CopilotStyle.accent.opacity(fillOpacity),
          in: RoundedRectangle(cornerRadius: CopilotStyle.cornerRadius)
        )
        .animation(.easeOut(duration: 0.12), value: isEnabled)
    }

    private var fillOpacity: Double {
      guard isEnabled else { return 0.4 }
      return configuration.isPressed ? 0.85 : 1
    }
  }
}
