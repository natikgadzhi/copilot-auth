# Security & Privacy

This app signs you in to Copilot Money and stores two Copilot credentials — a
Firebase **refresh token** and the public **API key** — in your macOS Keychain so
the [`copilot-python`](https://github.com/natikgadzhi/copilot-python) CLI can use
them. Those secrets are the whole reason to be careful, so here's exactly what the
app does and doesn't do with your data.

## The one file to read

All outbound crash telemetry lives in **[`App/Telemetry.swift`](App/Telemetry.swift)** —
the only file that imports Sentry (CI fails if a second file ever does). The
redaction it applies is the pure, unit-tested
[`Redaction`](Packages/CopilotAuthKit/Sources/CopilotAuthKit/Redaction.swift) in
the kit. Read those two and you know everything that can leave the machine.

## What leaves your Mac

| Destination | When | What | Never |
|---|---|---|---|
| **app.copilot.money** + Firebase (`securetoken` / `identitytoolkit`) | While you sign in | Your own Copilot email-link login + the Firebase token exchange — you authenticating to your own account | — |
| **Sentry** | Only if "Send anonymous crash reports" is ON | App version, OS version, a scrubbed crash stack trace, environment | The refresh token, the API key, any URL, any file path or username, breadcrumbs, screenshots, any user/install identifier |
| **Nothing else** | Ever | — | The Keychain item (your Copilot tokens) **never** leaves your Mac |

## Crash reports — what's in them, and how to turn them off

Crash reporting is **opt-out, default on**, and locked down hard:

- **Crashes and explicit errors only** — no usage analytics, no screen views, no
  timing, no breadcrumbs, no network/HTTP capture, no screenshots.
- **Anonymous** — no user id, no install id, no device id, no IP
  (`sendDefaultPii = false`); we never call `setUser`.
- **Scrubbed** — every event runs through `Redaction`: URLs dropped, `/Users/<you>`
  paths masked, anything token/key-shaped (`AIza…`, `Bearer …`, JWTs, long
  high-entropy blobs) masked. If anything secret-shaped *still* survives, the whole
  event is **dropped** (fail closed). Stack-frame symbol/type names are kept (they
  carry no data), so real crashes are still useful.

**Turn it off:** app menu → **Send anonymous crash reports** (uncheck). When off,
the Sentry SDK is **never even started** — not started-then-muted. Takes effect on
the next launch.

The Sentry **DSN is public on purpose** — it's an ingest key, not a read key, and
it's only baked into official notarized releases (local and open-source builds have
no DSN, so they never send anything).

## Keychain storage

The Copilot tokens live in a single Keychain item — service `io.respawn.copilot`,
account `copilot-session` — written with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: never synced to iCloud Keychain,
never in an unencrypted backup, readable only while your Mac is unlocked. It's
app-private by default; another tool (like `copilot.py`) reading it triggers a
one-time Keychain prompt you approve.

## Verifying the build

Don't take my word that the `.dmg` you ran was built from this source — check it:

1. **Checksum.** `shasum -a 256 CopilotAuth*.dmg` and confirm it matches the
   SHA-256 in the release notes / the `.sha256` asset.
2. **Provenance.** `gh attestation verify CopilotAuth*.dmg --repo natikgadzhi/copilot-auth`
   — confirms GitHub Actions built this exact file from this repo. (Add
   `--source-ref refs/tags/vX.Y.Z` to pin the tag.)
3. **Commit.** Open the app → menu → About; the line reads
   `Version X (build N) · abc1234`. Click `abc1234` (or compare it to the release
   tag's commit) — the running binary names its own source.

Build/sign/notarize happen only in GitHub Actions — no laptop is in the trust path.
Note: notarized macOS builds are **not** byte-reproducible (signing and
notarization embed timestamps/tickets), so we provide verifiable *provenance* — an
attestation, a checksum, and a visible commit — not byte-for-byte reproducibility.
