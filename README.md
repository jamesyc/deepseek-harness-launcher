# Deepseek Harness Launcher for macOS

macOS AppleScript launcher for the DeepSeek harness (`npx @deepseek-ai/dsh web`).

It starts the `dsh web` backend when the GUI starts (or attaches to a running one), opens the Chrome-app wrapper, and stops the backend it started when the GUI quits.

## Components

- `src/deepseek-harness-launcher.applescript` — launcher source. Stay-open AppleScript applet.
- `scripts/build.sh` — compiles `src/` into a signed `.app` (adds `LSUIElement`, re-signs).
- `scripts/install.sh` — installs to `~/Applications`, preserving the existing bundle's ID/icon.
- `scripts/verify.sh` — smoke-test for a built `.app` bundle.
- `examples/config.example` — commented sample config.
- `tests/` — shell tests + fixtures; `.github/workflows/ci.yml` runs them on macOS.
- `docs/CONFIG.md` — full configuration reference.

## What the launcher does

1. If another copy of the launcher is already running, focuses it and exits.
2. Checks port `3080` (see `serverPort`). If something other than the `dsh` server owns it, aborts with a dialog.
3. Otherwise starts the server in `~/.dsh/workspace`, logging to `~/Library/Logs/DeepSeek Harness.log` (rotates the previous log to `.1` when over 5 MB, then truncates on each start).
4. Waits (up to ~150s worst case: 60 tries × 1s curl timeout × 2 families + 0.5s delay) for `http://127.0.0.1:3080/` or `http://[::1]:3080/` to answer.
5. Locates the `DeepSeek Harness.app` Chrome app, opens it, and tracks its loader PID (exact executable match).
6. On `idle` (every 2s): quits when the Chrome app exits; notifies if the server dies unexpectedly.
7. On `quit`: `TERM`s the server it started (escalates to `KILL`), then quits.

It never kills a server it didn't start (`ownsServer` flag).

## Portability

No hardcoded usernames. Home-based paths resolve from `(path to home folder)` at runtime:

- workspace: `~/.dsh/workspace`
- log: `~/Library/Logs/DeepSeek Harness.log`

`dsh` resolution order: `/opt/homebrew/bin/mise` (Apple Silicon) → `/usr/local/bin/mise` (Intel) → `mise` on `PATH` → `npx -y @deepseek-ai/dsh` fallback.

Chrome-app search order: `~/Applications/<name>` → `~/Applications/Chrome Apps.localized/<name>` → `/Applications/<name>` → `/Applications/Chrome Apps.localized/<name>`. If none is found, a file picker asks once and the choice is cached in `~/Library/Application Support/DeepSeek Harness Launcher/ChromeAppPath` (survives reinstalls).

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

This compiles `src/`, embeds `assets/applet.icns`, adds `LSUIElement=true` (no Dock icon), and re-signs.
Output defaults to `build/DeepSeek Harness Launcher.app` (gitignored).

Manual alternative — Script Editor: open `src/deepseek-harness-launcher.applescript`,
File → Save as Application, check Stay open, name it `DeepSeek Harness Launcher`,
save to `~/Applications/`. (The manual app shows a Dock icon — `LSUIElement`
is only added by `build.sh`.)

## Install

```sh
./scripts/install.sh
# ./scripts/install.sh --from /tmp/My.app --to ~/Applications/"DeepSeek Harness Launcher.app"
```

Updates an existing install by transplanting only `main.scpt` + `applet.icns`
(keeps bundle ID and plist), or fresh-copies the build if none exists. Backs up the old bundle to
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
compiled output, config/handlers behave against fixtures (via the
`DEEPSEEK_HARNESS_CONFIG` and `DEEPSEEK_HARNESS_CACHE` overrides), Chrome-PID
matching fixtures, and a full build-then-verify round trip.
`.github/workflows/ci.yml` runs a fast Linux job (`shellcheck` + portable
tests) and a full `run.sh` job on `macos-latest`
(the AppleScript toolchain only exists on macOS).

## Settings

Build-time defaults live in the `property` lines at the top of
`src/deepseek-harness-launcher.applescript`; runtime overrides live in
`~/.config/deepseek-harness-launcher/config`. Full reference (keys, format,
precedence, picker cache): [`docs/CONFIG.md`](docs/CONFIG.md).

## Uninstall

```sh
rm -rf ~/Applications/"DeepSeek Harness Launcher.app"
# optional: config, log, workspace, picker cache
rm -rf ~/.config/deepseek-harness-launcher ~/Library/Logs/DeepSeek\ Harness.log ~/Library/Logs/DeepSeek\ Harness.log.1 ~/.dsh/workspace
rm -rf ~/Library/Application\ Support/DeepSeek\ Harness\ Launcher
```

`install.sh` keeps the 5 newest timestamped backups in `$TMPDIR`
(`DeepSeek-Harness-Launcher-backup-*.app`); older ones are pruned automatically.

## Troubleshooting

- **"Port 3080 is already in use"** — another program owns the port. Stop it
  or set `SERVER_PORT` in the config (the Chrome app must target the same port).
- **"DeepSeek Harness did not start"** — check the tail of the log:
  `tail -n 20 ~/Library/Logs/DeepSeek\ Harness.log` (or your `LOG_FILE`).
  Previous large logs rotate to `*.log.1`.
- **No Automation permission prompt is expected** — the launcher avoids
  System Events by design.
- `DEEPSEEK_HARNESS_CONFIG` only takes effect when launching from a terminal;
  Finder launches don't inherit shell environment.

## Note

The compiled `DeepSeek Harness Launcher.app` itself is not checked in — build it locally from source.
