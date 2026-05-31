import Foundation

/// The two scalars we pull out of the logged-in page.
public struct CapturedSecrets: Sendable, Equatable {
  public let apiKey: String
  public let refreshToken: String
}

/// How we extract the Firebase secrets from a logged-in Copilot page.
///
/// The Firebase web SDK persists the signed-in user in IndexedDB database
/// `firebaseLocalStorageDb`, object store `firebaseLocalStorage`, under a record
/// whose key is literally `firebase:authUser:<API_KEY>:[DEFAULT]`. So a single
/// read yields BOTH secrets: the API key falls out of the record's key, and the
/// refresh token is `value.stsTokenManager.refreshToken`.
public enum CopilotCapture {
  /// Body for `WKWebView.callAsyncJavaScript` — runs as an async function in the
  /// page, so top-level `await` and `return` are valid. Returns
  /// `{ apiKey, refreshToken }` once the user is authenticated, else `null`.
  ///
  /// NOTE: unverified against the live site; confirm the DB/store/key names in
  /// the Web Inspector on first run (see the design doc's contingency: fall back
  /// to intercepting the `securetoken`/`identitytoolkit` request).
  public static let indexedDBReadJS = """
    const db = await new Promise((resolve, reject) => {
      const req = indexedDB.open('firebaseLocalStorageDb');
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    const entries = await new Promise((resolve, reject) => {
      const store = db.transaction('firebaseLocalStorage', 'readonly')
        .objectStore('firebaseLocalStorage');
      const all = store.getAll();
      all.onsuccess = () => resolve(all.result);
      all.onerror = () => reject(all.error);
    });
    for (const entry of entries) {
      const key = entry.fbase_key || '';
      const match = key.match(/^firebase:authUser:([^:]+):/);
      const token = entry.value && entry.value.stsTokenManager
        && entry.value.stsTokenManager.refreshToken;
      if (match && token) {
        return { apiKey: match[1], refreshToken: token };
      }
    }
    return null;
    """

  /// Pure: validate the JS result into secrets. `nil` means "not yet — keep
  /// waiting" (user hasn't finished the login/2FA dance). Kept WebView-free so
  /// the completion logic is unit-testable.
  public static func parse(_ result: Any?) -> CapturedSecrets? {
    guard let dict = result as? [String: Any],
      let apiKey = dict["apiKey"] as? String, !apiKey.isEmpty,
      let refreshToken = dict["refreshToken"] as? String, !refreshToken.isEmpty
    else {
      return nil
    }
    return CapturedSecrets(apiKey: apiKey, refreshToken: refreshToken)
  }
}
