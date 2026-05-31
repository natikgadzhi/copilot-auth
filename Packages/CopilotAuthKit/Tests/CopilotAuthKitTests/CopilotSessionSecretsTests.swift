import Foundation
import Testing

@testable import CopilotAuthKit

@Suite("CopilotSessionSecrets")
struct CopilotSessionSecretsTests {
  @Test("encodes the webauth SecretBundle shape")
  func encodesBundleShape() throws {
    let secrets = CopilotSessionSecrets(
      refreshToken: "rt-123", apiKey: "AIzaXYZ",
      capturedAt: Date(timeIntervalSince1970: 1_717_200_000))
    let json =
      try JSONSerialization.jsonObject(with: secrets.encoded()) as? [String: Any]
    let values = json?["values"] as? [String: String]
    #expect(values?["refreshToken"] == "rt-123")
    #expect(values?["apiKey"] == "AIzaXYZ")
    #expect((json?["cookies"] as? [Any])?.isEmpty == true)
    #expect((json?["capturedAt"] as? Double) == 1_717_200_000)
  }

  @Test("round-trips through encode/decode")
  func roundTrips() throws {
    let original = CopilotSessionSecrets(
      refreshToken: "rt-abc", apiKey: "AIza-key",
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let restored = try CopilotSessionSecrets.decoded(from: original.encoded())
    #expect(restored == original)
  }

  @Test("decode rejects a bundle missing a required value")
  func decodeRejectsIncomplete() {
    let data = Data(
      #"{"cookies":[],"values":{"apiKey":"AIza"},"capturedAt":0}"#.utf8)
    #expect(throws: CopilotSecretError.incompleteBundle) {
      _ = try CopilotSessionSecrets.decoded(from: data)
    }
  }

  @Test("decode rejects an empty token value")
  func decodeRejectsEmpty() {
    let data = Data(
      #"{"cookies":[],"values":{"refreshToken":"","apiKey":"AIza"},"capturedAt":0}"#.utf8)
    #expect(throws: CopilotSecretError.incompleteBundle) {
      _ = try CopilotSessionSecrets.decoded(from: data)
    }
  }
}
