import Foundation

/// Pure text redaction for telemetry. Applied to the **value-bearing** fields of
/// a crash event (the exception message/value, file paths) — *never* to
/// symbol/type names. The goal: no Copilot credential, no URL, and no
/// username-bearing path can ever ride out in a crash report. Privacy-first —
/// when in doubt, over-redact, and the backstop drops the whole event.
///
/// Kept here in the kit (with no Sentry dependency) so the rot-prone regex logic
/// is unit-tested by plain `swift test`; `App/Telemetry.swift` is the only file
/// that imports Sentry and just applies these to the event's fields.
public enum Redaction {
  // Every pattern below matches a VALUE shape, not a type/symbol name. The token
  // run threshold (32) sits above this app's longest identifier so ordinary
  // crashes survive while real tokens (API key ~39, refresh token 200+) are cut.
  // `Regex` isn't Sendable, but these are immutable and matching never mutates
  // them, so reading them from any thread is safe.
  nonisolated(unsafe) private static let usernamePath = try! Regex(#"/Users/[^/\s"']+"#)
  nonisolated(unsafe) private static let url = try! Regex(#"https?://[^\s"'<>]+"#)
  nonisolated(unsafe) private static let googleAPIKey = try! Regex(#"AIza[0-9A-Za-z_\-]{20,}"#)
  nonisolated(unsafe) private static let bearer = try! Regex(#"(?i)bearer\s+[A-Za-z0-9._\-]+"#)
  nonisolated(unsafe) private static let jwtish = try! Regex(#"eyJ[A-Za-z0-9._\-]{10,}"#)
  nonisolated(unsafe) private static let longTokenRun = try! Regex(#"[A-Za-z0-9_\-]{32,}"#)
  nonisolated(unsafe) private static let sensitiveHost = try! Regex(
    #"(?i)(copilot\.money|securetoken|identitytoolkit)"#)

  /// Redact one value-bearing string: drop whole URLs, mask the username in
  /// `/Users/…` paths, and mask anything token/key-shaped.
  public static func scrubValue(_ string: String) -> String {
    var out = string.replacing(url, with: "<url>")
    out = out.replacing(usernamePath, with: "/Users/<redacted>")
    out = out.replacing(bearer, with: "Bearer <redacted>")
    out = out.replacing(googleAPIKey, with: "<redacted>")
    out = out.replacing(jwtish, with: "<redacted>")
    out = out.replacing(longTokenRun, with: "<redacted>")
    return out
  }

  /// Backstop: does this value still look like it carries a secret, a username
  /// path, or a Copilot/Firebase endpoint? If so the caller drops the whole event
  /// (fail closed). Only ever run on values — never on symbol/type names.
  public static func containsLeak(_ string: String) -> Bool {
    string.contains(usernamePath)
      || string.contains(url)
      || string.contains(googleAPIKey)
      || string.contains(jwtish)
      || string.contains(longTokenRun)
      || string.contains(bearer)
      || string.contains(sensitiveHost)
  }
}
