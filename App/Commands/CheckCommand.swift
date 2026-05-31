import ArgumentParser
import CopilotAuthKit

struct CheckCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check",
    abstract: "Check whether the stored Copilot session is still valid.")

  // No GUI/run-loop: the token probe is a plain HTTP request, so this is a
  // normal async CLI command.
  func run() async throws {
    switch await CopilotTokenProbe.run(secretStore: KeychainCopilotSecretStore()) {
    case .valid:
      print(SessionMessage.saved)
    case .expired:
      print("expired — run `authenticate` again")
      throw ExitCode(1)
    case .noStoredSession:
      print("no stored session — run `authenticate` first")
      throw ExitCode(2)
    }
  }
}
