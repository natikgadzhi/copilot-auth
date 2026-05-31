import Foundation
import Testing

@testable import CopilotAuthKit

@Suite("CopilotEndpoint.isTrustedSignInHost")
struct CopilotEndpointTests {
  private func trusts(_ string: String) -> Bool {
    CopilotEndpoint.isTrustedSignInHost(URL(string: string)!)
  }

  @Test("trusts the Copilot app and apex domain")
  func trustsCopilot() {
    #expect(trusts("https://app.copilot.money/auth/link?oobCode=x"))
    #expect(trusts("https://copilot.money/"))
  }

  @Test("trusts Firebase auth/hosting domains")
  func trustsFirebase() {
    #expect(trusts("https://copilot-money.firebaseapp.com/__/auth/action?oobCode=x"))
    #expect(trusts("https://copilot.web.app/"))
    #expect(trusts("https://identitytoolkit.googleapis.com/v1/accounts"))
  }

  @Test("rejects unknown and non-https hosts")
  func rejectsOthers() {
    #expect(!trusts("https://evil.example.com/copilot.money"))
    #expect(!trusts("http://app.copilot.money/"))
    #expect(!trusts("https://notcopilot.money/"))
    #expect(!trusts("https://firebaseapp.com.evil.com/"))
  }
}
