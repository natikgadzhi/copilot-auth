import Foundation

public enum CopilotSecretError: Error, Equatable {
  case incompleteBundle
}

/// The secrets we persist for `copilot.py`: the Firebase **refresh token** and
/// the public **API key**. From these `copilot.py` mints a fresh 1h ID token at
/// startup (`mint_id_token` → `securetoken.googleapis.com`).
///
/// Stored in the Keychain as the `webauth` **`SecretBundle`** JSON (see
/// `KeychainCopilotSecretStore`) rather than an opaque archive, so the item is:
///   - auditable by eye (security review), and
///   - readable by other tools, e.g.
///     `security find-generic-password -s io.respawn.copilot -w | jq -r '.values.refreshToken'`.
///
/// Security note for auditors: the refresh token IS a bearer credential for the
/// user's Copilot account. It lives only in the Keychain and is never logged.
public struct CopilotSessionSecrets: Sendable, Equatable {
  public let refreshToken: String
  public let apiKey: String
  public let capturedAt: Date

  public init(refreshToken: String, apiKey: String, capturedAt: Date = Date()) {
    self.refreshToken = refreshToken
    self.apiKey = apiKey
    self.capturedAt = capturedAt
  }

  /// One captured cookie in the `webauth` bundle. Copilot captures none (auth is
  /// token-based), so the array is always empty — but we keep the field so the
  /// on-disk shape matches the cross-tool `SecretBundle` schema exactly.
  private struct CookieField: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var secure: Bool
    var expiresAt: Double?
  }

  /// The cross-language `SecretBundle` shape:
  /// `{ cookies:[], values:{refreshToken,apiKey}, capturedAt:<epoch> }`.
  private struct Bundle: Codable {
    var cookies: [CookieField]
    var values: [String: String]
    var capturedAt: Double
  }

  public func encoded() throws -> Data {
    let bundle = Bundle(
      cookies: [],
      values: ["refreshToken": refreshToken, "apiKey": apiKey],
      capturedAt: capturedAt.timeIntervalSince1970)
    let encoder = JSONEncoder()
    // Compact (no .prettyPrinted): `security -w` hex-encodes any value containing
    // control bytes, so a pretty-printed bundle's newlines would force consumers
    // (and `… -w | jq`) to hex-decode first. Sorted keys keeps it diffable.
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(bundle)
  }

  public static func decoded(from data: Data) throws -> CopilotSessionSecrets {
    let bundle = try JSONDecoder().decode(Bundle.self, from: data)
    guard let refreshToken = bundle.values["refreshToken"], !refreshToken.isEmpty,
      let apiKey = bundle.values["apiKey"], !apiKey.isEmpty
    else {
      throw CopilotSecretError.incompleteBundle
    }
    return CopilotSessionSecrets(
      refreshToken: refreshToken,
      apiKey: apiKey,
      capturedAt: Date(timeIntervalSince1970: bundle.capturedAt))
  }
}
