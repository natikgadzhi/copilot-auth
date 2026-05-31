import Foundation
import Security

/// Where session secrets live. One protocol, two impls: Keychain for real use,
/// in-memory for tests.
public protocol CopilotSecretStoring: Sendable {
  func read() -> CopilotSessionSecrets?
  /// Returns whether the secrets actually persisted, so the caller doesn't report
  /// a session it couldn't store.
  @discardableResult func write(secrets: CopilotSessionSecrets) -> Bool
  func clear()
}

/// Test double. Not for production — holds secrets in process memory only.
public final class InMemoryCopilotSecretStore: CopilotSecretStoring, @unchecked Sendable {
  private var stored: CopilotSessionSecrets?
  public init() {}
  public func read() -> CopilotSessionSecrets? { stored }
  @discardableResult public func write(secrets: CopilotSessionSecrets) -> Bool {
    stored = secrets
    return true
  }
  public func clear() { stored = nil }
}

/// Keychain-backed store (a single generic-password item).
///
/// Why the Keychain: the refresh token is an account bearer token, so it gets
/// the OS's encrypted, access-controlled store rather than a file. The item is
/// keyed by service name only (single account per machine), so `write` deletes
/// any prior item first to avoid duplicates.
public final class KeychainCopilotSecretStore: CopilotSecretStoring, @unchecked Sendable {
  public static let defaultServiceName = "io.respawn.copilot"
  public static let defaultAccount = "copilot-session"
  private let serviceName: String
  private let account: String

  public init(
    serviceName: String = KeychainCopilotSecretStore.defaultServiceName,
    account: String = KeychainCopilotSecretStore.defaultAccount
  ) {
    self.serviceName = serviceName
    self.account = account
  }

  public func read() -> CopilotSessionSecrets? {
    var query = baseQuery()
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return try? CopilotSessionSecrets.decoded(from: data)
  }

  @discardableResult public func write(secrets: CopilotSessionSecrets) -> Bool {
    guard let data = try? secrets.encoded() else { return false }
    // Delete first by the bare primary key (service + account) so an item written
    // by an older build — with different accessibility — is still replaced.
    SecItemDelete(baseQuery() as CFDictionary)
    var attributes = baseQuery()
    attributes[kSecValueData] = data
    // The refresh token is a bearer credential, so pin it to this device: never
    // synced to iCloud Keychain, never in an unencrypted backup, and only
    // readable while the Mac is unlocked.
    attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  public func clear() {
    SecItemDelete(baseQuery() as CFDictionary)
  }

  private func baseQuery() -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: serviceName,
      kSecAttrAccount: account,
    ]
  }
}
