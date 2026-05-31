import Testing

@testable import CopilotAuthKit

@Suite("CopilotTokenProbe.classify")
struct CopilotTokenProbeTests {
  @Test("2xx means the refresh token is still valid")
  func validOnSuccess() {
    #expect(CopilotTokenProbe.classify(statusCode: 200) == .valid)
  }

  @Test("4xx means the refresh token was rejected / expired")
  func expiredOnClientError() {
    #expect(CopilotTokenProbe.classify(statusCode: 400) == .expired)
    #expect(CopilotTokenProbe.classify(statusCode: 401) == .expired)
  }
}
