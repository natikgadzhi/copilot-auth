/// Shared CLI wording so `authenticate` and `check` report a valid session the
/// same way — and name where the tokens actually live.
public enum SessionMessage {
  public static var saved: String {
    "Authenticated! Tokens saved in the macOS Keychain "
      + "(service \(KeychainCopilotSecretStore.defaultServiceName))."
  }
}
