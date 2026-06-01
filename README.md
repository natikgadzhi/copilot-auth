<p align="center">
  <img src="docs/logo.png" alt="Copilot Auth" width="128" height="128">
</p>

<h1 align="center">Copilot Auth</h1>

<p align="center">
  A tiny macOS app that signs you in to
  <a href="https://app.copilot.money">Copilot Money</a> and stores the secrets
  <a href="https://github.com/natikgadzhi/copilot-python"><code>copilot.py</code></a>
  needs to talk to Copilot's private GraphQL API.
</p>

It captures two values during a normal web login and saves them to your macOS
Keychain:

- `COPILOT_REFRESH_TOKEN` — the Firebase refresh token
- `FIREBASE_API_KEY` — the public web API key

`copilot.py` mints a fresh 1-hour ID token from these at startup, so you only run
this when the refresh token is revoked (rarely) — not on every sync.

## Install & sign in

**With Homebrew** (installs the app *and* puts `copilot-auth` on your PATH):

```sh
brew install --cask natikgadzhi/taps/copilot-auth
open -a "Copilot Auth"      # sign in once; or: copilot-auth authenticate
```

The cask drops **Copilot Auth.app** in `/Applications` and symlinks the
in-bundle binary to `copilot-auth` — the same layout `make install` produces.
`brew upgrade` then keeps it current.

**Or grab the DMG directly** — no toolchain, just the signed app:

1. **Download** the latest `CopilotAuth-X.Y.Z.dmg` from the
   [**Releases**](https://github.com/natikgadzhi/copilot-auth/releases/latest)
   page.
2. **Open** the DMG and drag **Copilot Auth** into **Applications**.
3. **Launch** Copilot Auth. It opens a real Copilot Money login window — do the
   normal email + password + 2FA. When it captures your session it stores the
   two secrets in your Keychain and quits.
4. **Use `copilot.py`.** It reads the Keychain automatically — nothing to copy or
   paste. The first read triggers a one-time Keychain prompt; click **Always
   Allow**.

That's it. Re-run Copilot Auth only if your session is revoked.

The app is signed with a Developer ID and notarized by Apple, so it opens with a
normal double-click. Want to verify the download first? See
[Verifying a release](#verifying-a-release).

## How it works

Copilot Auth opens a `WKWebView` at `app.copilot.money` and lets you log in
normally. After each navigation it reads the Firebase record out of the page's
IndexedDB (`firebaseLocalStorageDb` → the `firebase:authUser:<API_KEY>:[DEFAULT]`
entry), which yields **both** the API key (from the record's key) and the refresh
token (`value.stsTokenManager.refreshToken`). Once both are present it writes them
to the Keychain and quits.

It's built as an `.app` bundle (WKWebView's helper process requires one) but can
also be driven as a CLI (see [below](#use-it-from-the-terminal)).

## The stored secret (handoff contract)

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
manual-paste keep working.)

## Privacy & Security

The refresh token is a bearer credential for your Copilot account. It lives only
in the Keychain (`io.respawn.copilot`, device-only ACL), is never written to
logs/files/argv, and the capture JS result is never logged.

**What leaves your Mac:** while you sign in, the app talks to `app.copilot.money`
and Firebase (`securetoken` / `identitytoolkit`) **as you, with your own
account** — nothing else. Optional **crash reports** (opt-out, default on; app
menu → *Send anonymous crash reports*) send only an app version, OS version, and a
**scrubbed, anonymized** crash trace to Sentry — never the tokens, URLs, file
paths, or any identifier; anything secret-shaped that survives scrubbing drops the
whole event. Your Keychain tokens never leave the machine.

Full details and the egress table are in [SECURITY.md](SECURITY.md).

### Verifying a release

Every release is signed, notarized, and ships a SHA-256 and a SLSA build
provenance attestation. To verify a download:

```sh
shasum -a 256 -c CopilotAuth-*.dmg.sha256                       # checksum matches
gh attestation verify CopilotAuth-*.dmg --repo natikgadzhi/copilot-auth   # built by CI from the tagged commit
```

The running app's **About** panel shows the exact commit it was built from.

## Use it from the terminal

Copilot Auth doubles as a CLI. If you'd rather drive it from a shell, symlink the
in-bundle binary onto your PATH (drag the app to `/Applications` first):

```sh
ln -sf "/Applications/Copilot Auth.app/Contents/MacOS/Copilot Auth" "$(brew --prefix)/bin/copilot-auth"

copilot-auth authenticate   # opens the login window (the default)
copilot-auth check          # is the stored session still valid? (exit 0/1/2)
copilot-auth --help
```

A bare `copilot-auth` (or a Finder double-click of the app) runs `authenticate`.

## Build from source

You only need this to hack on the app — most people should just grab the DMG
above.

```sh
make contrib        # installs xcodegen, git hooks, generates the project
make authenticate   # build, open the login window, capture + store the session
make check          # is the stored session still valid? (exit 0/1/2)
make test           # CopilotAuthKit unit tests
make build          # compile the .app

make install        # .app -> /Applications, copilot-auth -> $(brew --prefix)/bin
make uninstall      # remove both
```

`make install` mirrors what a Homebrew cask does (app in `/Applications`, a
`copilot-auth` symlink on PATH). Override `APP_INSTALL_DIR` / `BIN_INSTALL_DIR`
(e.g. `~/Applications`, `~/bin`) to avoid writing to `/Applications`, or
`CONFIG=Release` to install the shipping build. Local builds are signed with
Developer ID so the Keychain item's no-prompt access survives rebuilds; CI builds
unsigned.

Releases are cut by the **Tag release** workflow (`workflow_dispatch` → pick a
patch/minor/major bump); it bumps the version, tags, and triggers the signed +
notarized release build.

## License

MIT — see [LICENSE](LICENSE).
