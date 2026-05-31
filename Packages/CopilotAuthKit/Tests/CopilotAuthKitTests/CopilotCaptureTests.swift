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

  @Test("parses a success result that also carries the ok flag")
  func okFlagIgnored() {
    let result = CopilotCapture.parse(["ok": true, "apiKey": "AIza", "refreshToken": "rt"])
    #expect(result == CapturedSecrets(apiKey: "AIza", refreshToken: "rt"))
  }

  @Test("diagnostic summarizes a miss without leaking secrets")
  func diagnosticSummary() {
    let miss: [String: Any] = [
      "ok": false, "dbNames": ["firebaseLocalStorageDb"], "keyCount": 3, "hasAuthUser": true,
    ]
    let summary = CopilotCapture.diagnostic(miss)
    #expect(summary == "dbs=[firebaseLocalStorageDb] records=3 hasAuthUser=true")
  }

  @Test("diagnostic handles a nil/garbage result")
  func diagnosticNil() {
    #expect(CopilotCapture.diagnostic(nil) == "no result")
  }

  @Test("signInPromptDetected reads the flag from a miss result")
  func signInPrompt() {
    #expect(CopilotCapture.signInPromptDetected(["ok": false, "signInPrompt": true]))
    #expect(!CopilotCapture.signInPromptDetected(["ok": false, "signInPrompt": false]))
    #expect(!CopilotCapture.signInPromptDetected(["ok": false]))
    #expect(!CopilotCapture.signInPromptDetected(nil))
  }
}
