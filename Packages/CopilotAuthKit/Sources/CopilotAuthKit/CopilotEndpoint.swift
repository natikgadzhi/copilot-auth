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

  /// Whether a pasted sign-in link points at a host we trust enough to load into
  /// the session web view without an extra confirmation: the Copilot app and the
  /// Firebase auth/hosting domains its email links come from. Anything else gets
  /// a confirm prompt (a phishing email could otherwise lure a paste).
  public static func isTrustedSignInHost(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    if host == "copilot.money" || host == "identitytoolkit.googleapis.com" { return true }
    let trustedSuffixes = [".copilot.money", ".firebaseapp.com", ".web.app"]
    return trustedSuffixes.contains { host == String($0.dropFirst()) || host.hasSuffix($0) }
  }
}
