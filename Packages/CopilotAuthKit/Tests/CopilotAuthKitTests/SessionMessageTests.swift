import Testing

@testable import CopilotAuthKit

@Suite("SessionMessage")
struct SessionMessageTests {
  @Test("announces success and names the Keychain service")
  func savedNamesTheStore() {
    let message = SessionMessage.saved
    #expect(message.contains("Authenticated!"))
    #expect(message.contains(KeychainCopilotSecretStore.defaultServiceName))
  }
}
