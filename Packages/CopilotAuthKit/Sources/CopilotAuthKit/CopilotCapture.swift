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
///
/// Firebase writes that record asynchronously *after* login completes — often
/// with no further navigation — so the caller polls this read rather than firing
/// it once. On a miss the JS returns a diagnostic (DB names, key count, whether
/// the auth record exists) instead of just null, so a failure is debuggable
/// without logging any secret.
public enum CopilotCapture {
  /// Body for `WKWebView.callAsyncJavaScript` — runs as an async function in the
  /// page. Returns `{ ok: true, apiKey, refreshToken }` once authenticated, else
  /// `{ ok: false, dbNames, keyCount, hasAuthUser, signInPrompt, error? }`. The
  /// `signInPrompt` flag (is Copilot showing its "we've sent a sign-in link"
  /// screen?) rides along so the caller needs only one round-trip per poll.
  public static let indexedDBReadJS = """
    const diag = { ok: false, dbNames: [], keyCount: 0, hasAuthUser: false };
    // The cue to reveal the paste field — a cheap text scan, on every miss.
    const pageText = (document.body ? document.body.innerText : "").toLowerCase();
    diag.signInPrompt = pageText.includes("sign-in link")
      || pageText.includes("sign in link")
      || pageText.includes("we've sent")
      || pageText.includes("we sent")
      || (pageText.includes("check your") && pageText.includes("email"));
    try {
      const dbs = indexedDB.databases ? await indexedDB.databases() : [];
      diag.dbNames = dbs.map((d) => d.name).filter(Boolean);
      if (!diag.dbNames.includes("firebaseLocalStorageDb")) {
        return diag;
      }
      const db = await new Promise((resolve, reject) => {
        const req = indexedDB.open("firebaseLocalStorageDb");
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
      const entries = await new Promise((resolve, reject) => {
        const store = db
          .transaction("firebaseLocalStorage", "readonly")
          .objectStore("firebaseLocalStorage");
        const all = store.getAll();
        all.onsuccess = () => resolve(all.result);
        all.onerror = () => reject(all.error);
      });
      diag.keyCount = entries.length;
      for (const entry of entries) {
        const key = entry.fbase_key || "";
        const match = key.match(/^firebase:authUser:([^:]+):/);
        if (match) {
          diag.hasAuthUser = true;
        }
        const token =
          entry.value && entry.value.stsTokenManager && entry.value.stsTokenManager.refreshToken;
        if (match && token) {
          return { ok: true, apiKey: match[1], refreshToken: token };
        }
      }
      return diag;
    } catch (err) {
      diag.error = String(err);
      return diag;
    }
    """

  /// Pure: validate the JS result into secrets. `nil` means "not captured yet"
  /// (keep polling). Kept WebView-free so the completion logic is unit-testable.
  public static func parse(_ result: Any?) -> CapturedSecrets? {
    guard let dict = result as? [String: Any],
      let apiKey = dict["apiKey"] as? String, !apiKey.isEmpty,
      let refreshToken = dict["refreshToken"] as? String, !refreshToken.isEmpty
    else {
      return nil
    }
    return CapturedSecrets(apiKey: apiKey, refreshToken: refreshToken)
  }

  /// A one-line, secret-free summary of a failed capture, for logging: which
  /// IndexedDB databases exist, how many records the Firebase store held, and
  /// whether any `firebase:authUser:…` record was present at all.
  public static func diagnostic(_ result: Any?) -> String {
    guard let dict = result as? [String: Any] else { return "no result" }
    let dbs = (dict["dbNames"] as? [String])?.joined(separator: ",") ?? "?"
    let keyCount = (dict["keyCount"] as? NSNumber)?.intValue ?? -1
    let hasAuthUser = (dict["hasAuthUser"] as? NSNumber)?.boolValue ?? false
    var summary = "dbs=[\(dbs)] records=\(keyCount) hasAuthUser=\(hasAuthUser)"
    if let error = dict["error"] as? String {
      summary += " error=\(error)"
    }
    return summary
  }

  /// Whether the read found Copilot's "we've sent a sign-in link" screen (the cue
  /// to reveal the paste field). Pure, for unit-testing the flag plumbing.
  public static func signInPromptDetected(_ result: Any?) -> Bool {
    ((result as? [String: Any])?["signInPrompt"] as? NSNumber)?.boolValue ?? false
  }
}
