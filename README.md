# Deepseek Harness Launcher for macOS

macOS AppleScript launcher for the DeepSeek harness (`npx @deepseek-ai/dsh web`).

It starts the `dsh web` backend when the GUI starts (or attaches to a running one), opens it in its own chromeless window, and stops the backend it started when the GUI quits.

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
2. Checks port `3080` (see `serverPort`). If something other than the `dsh` server owns it, aborts with a dialog. An adopted `dsh` server whose bare URL answers 401 (token fence) also aborts — the launcher never learns its token.
3. Otherwise starts the server in `~/.dsh/workspace` with `--port 0` (unless the command already sets `--port`), logging to `~/Library/Logs/DeepSeek Harness.log` (rotates the previous log to `.1` when over 5 MB, then truncates on each start).
4. Waits for the `dsh web: <url>` startup line in the log, then probes that URL directly (bare for old servers, `?token=…` for new ones — no version check needed).
5. Opens the URL in the bundled chromeless window (`Contents/Resources/DeepSeek Harness.app`: own Dock icon, no browser involved, token passed as argv). The window process exits with its last window, so it is PID-trackable; a crash orphan is stopped before launching. File > New Window (⌘N) opens another window on the same server; all windows share one backend, and closing the last one quits the launcher cascade.
6. Tracks the window PID — quits when the window exits, notifies if the server dies unexpectedly (checked every 2s in `idle`).
7. On `quit`: `TERM`s the server it started (escalates to `KILL`), then quits (the window is left open, as before).

It never kills a server it didn't start (`ownsServer` flag).

## Portability

No hardcoded usernames. Home-based paths resolve from `(path to home folder)` at runtime:

- workspace: `~/.dsh/workspace`
- log: `~/Library/Logs/DeepSeek Harness.log`

`dsh` resolution order: `/opt/homebrew/bin/mise` (Apple Silicon) → `/usr/local/bin/mise` (Intel) → `mise` on `PATH` → `npx -y @deepseek-ai/dsh` fallback.

No browser needed: the window is a tiny WebKit wrapper compiled from `src/window/` and nested inside the bundle, so per-token URLs just work with no Chrome, Safari, shortcuts, pickers, or caches.

## Configuration (optional)

All settings have working defaults. To override, create
`~/.config/deepseek-harness-launcher/config` — see `docs/CONFIG.md` for the full
reference and `examples/config.example` for a template:

```sh
# ~/.config/deepseek-harness-launcher/config
SERVER_PORT=3080
WORKSPACE=~/.dsh/workspace
```

## Prerequisites

- macOS (Apple Silicon or Intel — the window compiles natively via `swiftc`).
- One of: `mise` with `dsh` installed, or `node`/`npx` for the `@deepseek-ai/dsh` fallback.

No browser and no shortcut setup: the launcher ships its own window.

## Build

```sh
./scripts/build.sh
# custom output:
./scripts/build.sh --output /tmp/"DeepSeek Harness Launcher.app"
```

This compiles `src/` (AppleScript via `osacompile`, window via `swiftc`), embeds `assets/applet.icns` (both bundles share the whale), stamps canonical identity
from `assets/bundle-identity` (display name, icon file, `LSUIElement=true`
for no Dock icon on the launcher; the nested window keeps its Dock icon), and re-signs.
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

Replaces any existing install with a full copy of the build — identity and
icon ship from source (`assets/bundle-identity`, `assets/applet.icns`), so
nothing in the old bundle is kept. Backs up the old bundle to
`$TMPDIR` first, then re-signs and verifies.

## Verify

```sh
./scripts/verify.sh
# custom location:
./scripts/verify.sh /path/to/"DeepSeek Harness Launcher.app"
# or: DEEPSEEK_HARNESS_LAUNCHER_APP=/path/to/app ./scripts/verify.sh
```

Checks the bundle exists, `Info.plist` is valid with `LSUIElement=true`, the embedded script contains the server/window/`kill -TERM` strings, contains no hardcoded `/Users/<name>` path, `applet.icns` matches `assets/applet.icns`, and identity matches `assets/bundle-identity` (display name pinned, no `CFBundleIdentifier`/`CFBundleIconName`). Also checks the nested window bundle (executable, plist, pinned display name, matching icon) under `Contents/Resources/DeepSeek Harness.app`.

## Testing

```sh
./tests/run.sh
```

Runs `tests/test_*.sh`: AppleScript compiles, no `/Users/` paths in source or
compiled output, config/handlers behave against fixtures (via the
`DEEPSEEK_HARNESS_CONFIG` override), window-command fixtures, and a full
build-then-verify round trip.
`.github/workflows/ci.yml` runs a fast Linux job (`shellcheck` + portable
tests) and a full `run.sh` job on `macos-latest`
(the AppleScript toolchain only exists on macOS).

## Settings

Build-time defaults live in the `property` lines at the top of
`src/deepseek-harness-launcher.applescript`; runtime overrides live in
`~/.config/deepseek-harness-launcher/config`. Full reference (keys, format,
precedence): [`docs/CONFIG.md`](docs/CONFIG.md).

## Uninstall

```sh
rm -rf ~/Applications/"DeepSeek Harness Launcher.app"
# optional: config, log, workspace, window web data
rm -rf ~/.config/deepseek-harness-launcher ~/Library/Logs/DeepSeek\ Harness.log ~/Library/Logs/DeepSeek\ Harness.log.1 ~/.dsh/workspace
rm -rf ~/Library/Application\ Support/DeepSeek\ Harness\ Launcher ~/Library/WebKit/local.deepseek-harness.window
```

`install.sh` keeps the 5 newest timestamped backups in `$TMPDIR`
(`DeepSeek-Harness-Launcher-backup-*.app`); older ones are pruned automatically.

## Troubleshooting

- **"Port 3080 is already in use"** — another program owns the port. Stop it
  or set `SERVER_PORT` in the config.
- **"DeepSeek Harness did not start"** — check the tail of the log:
  `tail -n 20 ~/Library/Logs/DeepSeek\ Harness.log` (or your `LOG_FILE`).
  Previous large logs rotate to `*.log.1`. The server must print a
  `dsh web: <url>` line — without it the launcher never finds the port.
- **"The DeepSeek Harness window did not open"** — the nested window bundle
  is damaged; rebuild and reinstall.
- **"The window component is missing"** — same, but detected before launch
  (hand-built Script Editor copies have no nested bundle).
- **"The running server requires authentication"** — a token-fenced `dsh`
  already owns the port. Stop it and relaunch so the launcher starts the
  server itself, or open the token URL printed by `dsh web` yourself.
- **No Automation permission prompt is expected** — the launcher avoids
  System Events by design.
- `DEEPSEEK_HARNESS_CONFIG` only takes effect when launching from a terminal;
  Finder launches don't inherit shell environment.

## Note

The compiled `DeepSeek Harness Launcher.app` itself is not checked in — build it locally from source.
