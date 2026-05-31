import ArgumentParser
import Foundation

@main
struct CopilotAuth: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "copilot-auth",
    abstract: "Sign in to Copilot Money and store the session for copilot.py.",
    version: "0.1.0",
    subcommands: [AuthenticateCommand.self, CheckCommand.self],
    // No subcommand (bare `copilot-auth`, or a Finder double-click of the .app)
    // opens the login window — the most useful default for a GUI sign-in tool.
    defaultSubcommand: AuthenticateCommand.self)

  /// Custom entry point so we can drop the launch arguments Xcode/AppKit inject
  /// (e.g. `-NSDocumentRevisionsDebugMode YES`, `-ApplePersistenceIgnoreState`),
  /// which argument-parser would otherwise reject as unknown options.
  static func main() async {
    do {
      var command = try parseAsRoot(userArguments())
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      exit(withError: error)
    }
  }

  private static func userArguments() -> [String] {
    var result: [String] = []
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
      if arg.hasPrefix("-NS") || arg.hasPrefix("-Apple") {
        _ = iterator.next()  // skip the injected option's value
        continue
      }
      result.append(arg)
    }
    return result
  }
}
