# Deepseek Harness Launcher for macOS

macOS AppleScript launcher for the DeepSeek harness (`npx @deepseek-ai/dsh web`).

It starts the `dsh web` backend when the GUI starts, opens the Chrome-app wrapper, and stops the backend when the GUI quits.

## Components

- `src/deepseek-harness-launcher.applescript` — launcher source. Stay-open AppleScript applet.
- `scripts/build.sh` — compiles `src/` into a signed `.app` (adds `LSUIElement`, re-signs).
- `scripts/install.sh` — installs to `~/Applications`, preserving the existing bundle's ID/icon.
- `scripts/verify.sh` — smoke-test for a built `.app` bundle.
- `examples/config.example` — commented sample config.
- `tests/` — shell tests + fixtures; `.github/workflows/ci.yml` runs them on macOS.
- `docs/CONFIG.md` — full configuration reference.

## What the launcher does

1. Checks port `3080` (see `serverPort`). If something other than `@deepseek-ai/dsh` owns it, aborts with a dialog.
2. Otherwise starts the server in `~/.dsh/workspace`, logging to `~/Library/Logs/DeepSeek Harness.log`.
3. Waits (up to ~30s) for `http://127.0.0.1:3080/` to answer.
4. Locates the `DeepSeek Harness.app` Chrome app, opens it, and tracks its `app_mode_loader` PID.
5. On `idle` (every 2s): quits when the Chrome app exits; notifies if the server dies unexpectedly.
6. On `quit`: `TERM`s the server it started (escalates to `KILL`), then quits.

It never kills a server it didn't start (`ownsServer` flag).

## Portability

No hardcoded usernames. Home-based paths resolve from `(path to home folder)` at runtime:

- workspace: `~/.dsh/workspace`
- log: `~/Library/Logs/DeepSeek Harness.log`

`dsh` resolution order: `/opt/homebrew/bin/mise` (Apple Silicon) → `/usr/local/bin/mise` (Intel) → `mise` on `PATH` → `npx -y @deepseek-ai/dsh` fallback.

Chrome-app search order: `~/Applications/<name>` → `~/Applications/Chrome Apps.localized/<name>` → `/Applications/<name>` → `/Applications/Chrome Apps.localized/<name>`. If none is found, a file picker asks once and the choice is cached in the applet's `resolvedChromeAppPath` property.

## Configuration (optional)

All settings have working defaults. To override, create
`~/.config/deepseek-harness-launcher/config` — see `docs/CONFIG.md` for the full
reference and `examples/config.example` for a template:

```sh
# ~/.config/deepseek-harness-launcher/config
SERVER_PORT=3080
WORKSPACE=~/.dsh/workspace
CHROME_APP=~/Applications/Chrome Apps.localized/DeepSeek Harness.app
```

## Prerequisites

- macOS with Chrome + a Chrome app for `http://127.0.0.1:3080` named `DeepSeek Harness`
  (Chrome → More Tools → Create Shortcut → Open as window, or `⋮` → Cast, save and share → Install page as app).
- One of: `mise` with `dsh` installed, or `node`/`npx` for the `@deepseek-ai/dsh` fallback.

## Build

```sh
./scripts/build.sh
# custom output:
./scripts/build.sh --output /tmp/"DeepSeek Harness Launcher.app"
```

This compiles `src/`, adds `LSUIElement=true` (no Dock icon), and re-signs.
Output defaults to `build/DeepSeek Harness Launcher.app` (gitignored).

Manual alternative — Script Editor: open `src/deepseek-harness-launcher.applescript`,
File → Save as Application, check Stay open, name it `DeepSeek Harness Launcher`,
save to `~/Applications/`.

## Install

```sh
./scripts/install.sh
# ./scripts/install.sh --from /tmp/My.app --to ~/Applications/"DeepSeek Harness Launcher.app"
```

Updates an existing install by transplanting only `main.scpt` (keeps bundle ID
and icon), or fresh-copies the build if none exists. Backs up the old bundle to
`$TMPDIR` first, then re-signs and verifies.

## Verify

```sh
./scripts/verify.sh
# custom location:
./scripts/verify.sh /path/to/"DeepSeek Harness Launcher.app"
# or: DEEPSEEK_HARNESS_LAUNCHER_APP=/path/to/app ./scripts/verify.sh
```

Checks the bundle exists, `Info.plist` is valid with `LSUIElement=true`, the embedded script contains the server/Chrome-app/`kill -TERM` strings, contains no hardcoded `/Users/<name>` path, and `applet.icns` exists.

## Testing

```sh
./tests/run.sh
```

Runs `tests/test_*.sh`: AppleScript compiles, no `/Users/` paths in source or
compiled output, config handlers behave against fixtures (via the
`DEEPSEEK_HARNESS_CONFIG` override — set it to point the launcher at a test
config instead of `~/.config/...`), and a full build-then-verify round trip.
`.github/workflows/ci.yml` runs `shellcheck` + `run.sh` on `macos-latest`
(the AppleScript toolchain only exists on macOS).

## Settings

Edit the `property` lines at the top of `src/deepseek-harness-launcher.applescript`:

| Property | Default | Notes |
|---|---|---|
| `serverPort` | `3080` | Used for the URL, `lsof` checks, and dialogs |
| `chromeAppName` | `DeepSeek Harness.app` | Searched in `~/Applications` and `/Applications`, with and without `Chrome Apps.localized` |
| `resolvedChromeAppPath` | `""` | Leave empty; auto-filled after first file-picker use |

## Note

The compiled `DeepSeek Harness Launcher.app` itself is not checked in — build it locally from source.
