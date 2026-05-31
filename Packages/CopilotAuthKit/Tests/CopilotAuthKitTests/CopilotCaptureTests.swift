import Foundation
import Testing

@testable import CopilotAuthKit

@Suite("CopilotCapture.parse")
struct CopilotCaptureTests {
  @Test("returns secrets when both scalars are present")
  func bothPresent() {
    let result = CopilotCapture.parse(["apiKey": "AIza", "refreshToken": "rt"])
    #expect(result == CapturedSecrets(apiKey: "AIza", refreshToken: "rt"))
  }

  @Test("returns nil when the result is null (not logged in yet)")
  func nullResult() {
    #expect(CopilotCapture.parse(nil) == nil)
  }

  @Test("returns nil when a scalar is missing")
  func missingScalar() {
    #expect(CopilotCapture.parse(["apiKey": "AIza"]) == nil)
  }

  @Test("returns nil when a scalar is empty")
  func emptyScalar() {
    #expect(CopilotCapture.parse(["apiKey": "AIza", "refreshToken": ""]) == nil)
  }
}
