# copilot-auth

A tiny macOS app that signs you in to [Copilot Money](https://app.copilot.money)
in a real web view and stores the two secrets [`copilot.py`][copilot-python]
needs to talk to Copilot's private GraphQL API:

- `COPILOT_REFRESH_TOKEN` — the Firebase refresh token
- `FIREBASE_API_KEY` — the public web API key

`copilot.py` mints a fresh 1-hour ID token from these at startup, so you only run
this when the refresh token is revoked (rarely) — not on every sync.

It's a near-clone of a sibling project's auth flow and follows a shared
`webauth` token-capture design; per that design the shared framework is **not**
extracted yet — this copies ~150 lines of the proven pattern.

## How it works

`authenticate` opens a `WKWebView` at `app.copilot.money`. You do the normal
email/password + 2FA login. After each navigation it reads the Firebase record
out of the page's IndexedDB (`firebaseLocalStorageDb` → the
`firebase:authUser:<API_KEY>:[DEFAULT]` entry), which yields **both** the API key
(from the record's key) and the refresh token
(`value.stsTokenManager.refreshToken`). Once both are present it writes them to
the Keychain and quits.

The app is built as an `.app` bundle (WKWebView's helper process requires one)
but driven as a CLI.

## Build & run

```sh
make contrib        # installs xcodegen, git hooks, generates the project
make authenticate   # build, open the login window, capture + store the session
make check          # is the stored session still valid? (exit 0/1/2)
make test           # CopilotAuthKit unit tests
make build          # compile the .app
```

Signed with Developer ID so the Keychain item's no-prompt access survives
rebuilds. CI builds unsigned.

## Stored secret (the handoff contract)

One Keychain `genericPassword` item — service `io.respawn.copilot`, account
`copilot-session` — holding a `SecretBundle` JSON:

```json
{ "cookies": [], "values": { "refreshToken": "...", "apiKey": "AIza..." }, "capturedAt": 1717200000 }
```

Any tool can read it:

```sh
security find-generic-password -s io.respawn.copilot -w | jq -r '.values.refreshToken'
```

`copilot.py` reads it automatically: if `COPILOT_REFRESH_TOKEN` /
`FIREBASE_API_KEY` aren't already in the environment or `.env`, it shells out to
`security` and parses this bundle. (Environment and `.env` always win, so CI and
manual-paste keep working.) The first such read triggers a one-time Keychain
prompt — click **Always Allow**.

## Security

The refresh token is a bearer credential for your Copilot account. It lives only
in the Keychain, is never written to logs/files/argv, and the capture JS result
is never logged.

## License

MIT — see [LICENSE](LICENSE).

[copilot-python]: https://github.com/natikgadzhi/copilot-python
