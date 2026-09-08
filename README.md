# deepseek-harness-launcher

macOS AppleScript launcher for the DeepSeek harness (`npx @deepseek-ai/dsh web`).

It starts the `dsh web` backend when the GUI starts, opens the Chrome-app wrapper, and stops the backend when the GUI quits.

## Components

- `deepseek-harness-launcher.applescript` — launcher source. Stay-open AppleScript applet.
- `verify-deepseek-harness-launcher.sh` — smoke-test for the built `.app` bundle.

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

## Prerequisites

- macOS with Chrome + a Chrome app for `http://127.0.0.1:3080` named `DeepSeek Harness`
  (Chrome → More Tools → Create Shortcut → Open as window, or `⋮` → Cast, save and share → Install page as app).
- One of: `mise` with `dsh` installed, or `node`/`npx` for the `@deepseek-ai/dsh` fallback.

## Build

Option A — Script Editor: open `deepseek-harness-launcher.applescript`, File → Save as Application, check Stay open, name it `DeepSeek Harness Launcher`, save to `~/Applications/`.

Option B — command line:

```sh
osacompile -s -o ~/Applications/"DeepSeek Harness Launcher.app" deepseek-harness-launcher.applescript
# Stay-open applets built with osacompile lack LSUIElement; add it so the
# launcher runs without a Dock icon, then re-sign (editing Info.plist
# invalidates the original signature):
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" ~/Applications/"DeepSeek Harness Launcher.app"/Contents/Info.plist
codesign --force --deep --sign - ~/Applications/"DeepSeek Harness Launcher.app"
```

## Verify

```sh
./verify-deepseek-harness-launcher.sh
# custom location:
./verify-deepseek-harness-launcher.sh /path/to/"DeepSeek Harness Launcher.app"
# or: DEEPSEEK_HARNESS_LAUNCHER_APP=/path/to/app ./verify-deepseek-harness-launcher.sh
```

Checks the bundle exists, `Info.plist` is valid with `LSUIElement=true`, the embedded script contains the server/Chrome-app/`kill -TERM` strings, contains no hardcoded `/Users/<name>` path, and `applet.icns` exists.

## Settings

Edit the `property` lines at the top of the `.applescript`:

| Property | Default | Notes |
|---|---|---|
| `serverPort` | `3080` | Used for the URL, `lsof` checks, and dialogs |
| `chromeAppName` | `DeepSeek Harness.app` | Searched in `~/Applications` and `/Applications`, with and without `Chrome Apps.localized` |
| `resolvedChromeAppPath` | `""` | Leave empty; auto-filled after first file-picker use |

## Note

The compiled `DeepSeek Harness Launcher.app` itself is not checked in — build it locally from source.
