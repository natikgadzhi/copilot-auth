import Foundation
import Testing

@testable import CopilotAuthKit

@Suite("CopilotAuthManager")
@MainActor
struct CopilotAuthManagerTests {
  @Test("captured secrets authenticate and persist")
  func ingestComplete() {
    let store = InMemoryCopilotSecretStore()
    let manager = CopilotAuthManager(secretStore: store)
    manager.ingest(captured: CapturedSecrets(apiKey: "AIza", refreshToken: "rt"))
    #expect(manager.state == .authenticated)
    #expect(store.read()?.refreshToken == "rt")
    #expect(store.read()?.apiKey == "AIza")
  }

  @Test("nil capture does not authenticate or persist")
  func ingestNil() {
    let store = InMemoryCopilotSecretStore()
    let manager = CopilotAuthManager(secretStore: store)
    manager.ingest(captured: nil)
    #expect(manager.state != .authenticated)
    #expect(store.read() == nil)
  }

  @Test("initSessionFromSecureStorage restores a stored session")
  func restore() {
    let store = InMemoryCopilotSecretStore()
    store.write(secrets: CopilotSessionSecrets(refreshToken: "rt", apiKey: "AIza"))
    let manager = CopilotAuthManager(secretStore: store)
    manager.initSessionFromSecureStorage()
    #expect(manager.state == .authenticated)
    #expect(manager.secrets?.refreshToken == "rt")
  }

  @Test("reset clears stored secrets")
  func reset() {
    let store = InMemoryCopilotSecretStore()
    store.write(secrets: CopilotSessionSecrets(refreshToken: "rt", apiKey: "AIza"))
    let manager = CopilotAuthManager(secretStore: store)
    manager.reset()
    #expect(manager.state == .unauthenticated)
    #expect(store.read() == nil)
  }
}
