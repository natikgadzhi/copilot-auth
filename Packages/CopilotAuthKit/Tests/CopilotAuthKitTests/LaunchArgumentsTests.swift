import Testing

@testable import CopilotAuthKit

@Suite("LaunchArguments.user")
struct LaunchArgumentsTests {
  @Test("passes real arguments through untouched")
  func realArguments() {
    #expect(LaunchArguments.user(from: []) == [])
    #expect(LaunchArguments.user(from: ["check"]) == ["check"])
    #expect(LaunchArguments.user(from: ["reset", "--foo", "bar"]) == ["reset", "--foo", "bar"])
  }

  @Test("drops AppKit-injected -NS / -Apple options and their values")
  func dropsInjectedOptions() {
    let raw = [
      "-NSDocumentRevisionsDebugMode", "YES", "authenticate",
      "-ApplePersistenceIgnoreState", "0",
    ]
    #expect(LaunchArguments.user(from: raw) == ["authenticate"])
  }

  @Test("a Finder launch (only injected args) reduces to no args → default subcommand")
  func bareGuiLaunch() {
    #expect(LaunchArguments.user(from: ["-NSDocumentRevisionsDebugMode", "YES"]) == [])
  }
}
