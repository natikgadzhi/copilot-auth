import Foundation

public enum CopilotAuthResult: Sendable, Equatable {
  case valid
  case expired
  case noStoredSession
}

/// Headless session check for the `check` command.
///
/// Why plain URLSession (not WKWebView): validity is decided entirely by whether
/// the Firebase Secure Token service still accepts the refresh token — exactly
/// what `copilot.py`'s `mint_id_token` does. So we replay that one POST and read
/// the status code; no GUI/app-bundle rendering required.
public enum CopilotTokenProbe {
  /// Pure: classify an HTTP status from the token endpoint. A fresh ID token
  /// comes back 2xx; a revoked/expired refresh token is rejected 4xx.
  public static func classify(statusCode: Int) -> CopilotAuthResult {
    (200..<300).contains(statusCode) ? .valid : .expired
  }

  public static func run(secretStore: any CopilotSecretStoring) async -> CopilotAuthResult {
    guard let secrets = secretStore.read() else { return .noStoredSession }

    var components = URLComponents(
      url: CopilotEndpoint.secureToken.url, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "key", value: secrets.apiKey)]

    var request = URLRequest(url: components.url!)
    request.httpMethod = "POST"
    request.setValue(
      "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let refresh =
      secrets.refreshToken.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
      ?? secrets.refreshToken
    request.httpBody = "grant_type=refresh_token&refresh_token=\(refresh)".data(using: .utf8)

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      let code = (response as? HTTPURLResponse)?.statusCode ?? 500
      return classify(statusCode: code)
    } catch {
      return .expired
    }
  }
}
