import Foundation

/// The Copilot / Firebase URLs the auth layer touches.
public enum CopilotEndpoint: Sendable {
  /// Where we send the login web view; Copilot redirects to its sign-in screen
  /// when the user isn't authenticated yet.
  case app
  /// Firebase Secure Token service — exchanges the refresh token for a fresh ID
  /// token. We use it (without rendering anything) to validate stored secrets.
  case secureToken

  public var url: URL {
    switch self {
    case .app:
      return URL(string: "https://app.copilot.money/")!
    case .secureToken:
      return URL(string: "https://securetoken.googleapis.com/v1/token")!
    }
  }
}
