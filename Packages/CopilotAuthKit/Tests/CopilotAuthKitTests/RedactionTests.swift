import Testing

@testable import CopilotAuthKit

@Suite("Redaction")
struct RedactionTests {
  @Test("scrubs a magic-link URL (oobCode and all)")
  func scrubsURL() {
    let scrubbed = Redaction.scrubValue(
      "failed to load https://app.copilot.money/auth/link?oobCode=ABC123&lang=en here")
    #expect(scrubbed == "failed to load <url> here")
    #expect(!Redaction.containsLeak(scrubbed))
  }

  @Test("masks the username in a /Users path")
  func scrubsUsernamePath() {
    #expect(Redaction.scrubValue("/Users/natik/Library/x") == "/Users/<redacted>/Library/x")
  }

  @Test("masks a Google API key, a Bearer token, and a JWT")
  func scrubsSecrets() {
    #expect(
      Redaction.scrubValue("key AIzaSyA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7") == "key <redacted>")
    #expect(
      Redaction.scrubValue("Authorization: Bearer abc.def.ghi")
        == "Authorization: Bearer <redacted>")
    #expect(Redaction.scrubValue("token eyJhbGciOiJSUzI1NiIsImtpZCI6") == "token <redacted>")
  }

  @Test("masks a long refresh-token-shaped blob")
  func scrubsLongToken() {
    let token = String(repeating: "a1B2c3", count: 10)  // 60 chars
    #expect(Redaction.scrubValue("rt=\(token)") == "rt=<redacted>")
  }

  @Test("leaves benign crash text and our own symbol names alone")
  func keepsBenignText() {
    let benign = "Fatal error: Index 5 is out of range for count 3"
    #expect(Redaction.scrubValue(benign) == benign)
    let symbol = "CopilotAuthKit.CopilotAuthManager.ingest(captured:)"
    #expect(Redaction.scrubValue(symbol) == symbol)
    #expect(!Redaction.containsLeak(symbol))  // the critical false-positive guard
    #expect(!Redaction.containsLeak(benign))
  }

  @Test("backstop flags raw secrets, paths, and Copilot endpoints")
  func backstopCatchesLeaks() {
    #expect(Redaction.containsLeak("AIzaSyA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7"))
    #expect(Redaction.containsLeak("/Users/natik/secret"))
    #expect(Redaction.containsLeak("could not reach copilot.money"))
    #expect(Redaction.containsLeak("POST securetoken.googleapis.com failed"))
  }
}
