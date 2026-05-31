import ArgumentParser
import CopilotAuthKit
import Foundation

@main
struct CopilotAuth: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "copilot-auth",
    abstract: "Sign in to Copilot Money and store the session for copilot.py.",
    version: "0.1.0",
    subcommands: [AuthenticateCommand.self, CheckCommand.self, ResetCommand.self],
    // No subcommand (bare `copilot-auth`, or a Finder double-click of the .app)
    // opens the login window — the most useful default for a GUI sign-in tool.
    defaultSubcommand: AuthenticateCommand.self)

  /// Custom entry point so we can drop the launch arguments Xcode/AppKit inject
  /// (e.g. `-NSDocumentRevisionsDebugMode YES`, `-ApplePersistenceIgnoreState`),
  /// which argument-parser would otherwise reject as unknown options.
  static func main() async {
    do {
      let args = LaunchArguments.user(from: Array(CommandLine.arguments.dropFirst()))
      var command = try parseAsRoot(args)
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      exit(withError: error)
    }
  }
}
