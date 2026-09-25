# Single Swift app refactor

## Product contract

- A single macOS app owns every WebKit window and its native Settings window.
- The app requires an installed `dsh`. A missing executable is an error; it never invokes `npx` to install one.
- If a `dsh web` process is already listening, attach and never stop it on exit. Use its printed token URL from an open log where available. Settings accepts a token URL for terminal-launched servers without an accessible log.
- Otherwise start `dsh web --no-open --port 0`. Stop only this child when the last Harness window closes or the app quits.
- File > New Window opens another WebKit window against the same server.
- Users set executable, workspace, and optional existing-server URL in the Swift Settings window. The URL is stored in Keychain.
- GitHub CI builds, tests, and packages a universal `.app` zip. The old AppleScript app, nested window bundle, shell config, and installer are removed.

## Implementation

1. `LauncherCore` owns URL validation, settings persistence, executable resolution, running-server discovery, and child process lifecycle. `DeepSeekHarnessLauncher` is the only executable.
2. AppKit owns the Settings and WebKit windows. The existing window bundle identifier is retained for WebKit data continuity.
3. A fake `dsh` fixture runs a real loopback HTTP server in tests. Tests cover token/bare URLs, attach with and without logs, IPv6, early exit, timeouts, ownership, Keychain settings, AppKit windows, and the package archive.
4. `scripts/package.sh` builds arm64 and x86_64 release binaries, combines them with `lipo`, signs the app, and creates a zip and checksum. `.github/workflows/ci.yml` uploads the package on CI and publishes tag builds as releases.

## Verification gates

- `swift test`: all core and AppKit tests pass.
- `./tests/test_package.sh`: verify the real universal binary, plist, identifier, signature, zip contents, and checksum.
- Manual macOS smoke: attach to an already running token-gated server, open a second window, open Settings, close both windows, and verify the attached server survives.
- Owned-server integration: the fake `dsh` starts as a real child process and HTTP listener; tests verify startup, last-window callback, unexpected exit, and termination. A full GUI launch with an owned server was not run because a user-owned `dsh` was already listening on this Mac.

## Known release limit

Pull-request artifacts remain ad hoc signed. The tag release job now imports a Developer ID identity, creates a temporary notary profile, signs with hardened runtime and timestamp, notarizes, staples, verifies Gatekeeper, and publishes the final archive. Its first live run remains pending until the `release` environment secrets in `docs/RELEASING.md` are configured.
