import ArgumentParser
import CopilotAuthKit
import Foundation
import WebKit

struct ResetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "reset",
    abstract: "Sign out from scratch: clear the stored session, web view data, and caches.")

  @MainActor
  func run() async throws {
    // Needs a run loop for WKWebsiteDataStore's async removal; no window shown.
    AppRunLoop.runHeadless {
      KeychainCopilotSecretStore().clear()

      let store = WKWebsiteDataStore.default()
      await store.removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
      URLCache.shared.removeAllCachedResponses()

      print("Cleared the stored Copilot session, web view data, and caches.")
    }
  }
}
