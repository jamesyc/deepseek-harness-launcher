# deepseek-harness-launcher

macOS AppleScript launcher for the DeepSeek harness (`npx @deepseek-ai/dsh web`).

It starts the `dsh web` backend when the GUI starts, opens the Chrome-app wrapper, and stops the backend when the GUI quits.

## Components

- `deepseek-harness-launcher.applescript` — launcher source. Stay-open AppleScript applet.
- `verify-deepseek-harness-launcher.sh` — smoke-test for the built `.app` bundle.

## What the launcher does

1. Checks port `3080`. If something other than `@deepseek-ai/dsh` owns it, aborts with a dialog.
2. Otherwise starts the server in `/Users/jameschang/.dsh/workspace`:
   `mise exec -- dsh web --no-open`, logging to `~/Library/Logs/DeepSeek Harness.log`.
3. Waits (up to ~30s) for `http://127.0.0.1:3080/` to answer.
4. Opens the Chrome app at `~/Applications/Chrome Apps.localized/DeepSeek Harness.app` and tracks its `app_mode_loader` PID.
5. On `idle` (every 2s): quits when the Chrome app exits; notifies if the server dies unexpectedly.
6. On `quit`: `TERM`s the server it started (escalates to `KILL`), then quits.

It never kills a server it didn't start (`ownsServer` flag).

## Prerequisites

- macOS with Chrome + a Chrome app for `http://127.0.0.1:3080` named `DeepSeek Harness`
  (Chrome → More Tools → Create Shortcut → Open as window, or `⋮` → Cast, save and share → Install page as app).
- `dsh` available via `mise` (`/opt/homebrew/bin/mise exec -- dsh ...`), or edit the `launchCommand` in the `.applescript` to call `dsh` directly.

## Build

Option A — Script Editor: open `deepseek-harness-launcher.applescript`, File → Save as Application, check Stay open, name it `DeepSeek Harness Launcher`, save to `~/Applications/`.

Option B — command line:

```sh
osacompile -s -o ~/Applications/"DeepSeek Harness Launcher.app" deepseek-harness-launcher.applescript
```

The bundle ID in the checked-in build was `com.jameschang.deepseek-harness-launcher`.

## Verify

```sh
./verify-deepseek-harness-launcher.sh
```

Checks the bundle exists, `Info.plist` is valid with `LSUIElement=true`, the embedded script contains the server/Chrome-app/`kill -TERM` strings, and `applet.icns` exists.

## Adapting paths

Hardcoded defaults in the `.applescript` (edit the `property` lines at the top):

| Property | Default |
|---|---|
| `serverURL` | `http://127.0.0.1:3080/` |
| `workspacePath` | `/Users/jameschang/.dsh/workspace` |
| `logPath` | `/Users/jameschang/Library/Logs/DeepSeek Harness.log` |
| `chromeAppPath` | `/Users/jameschang/Applications/Chrome Apps.localized/DeepSeek Harness.app` |

## Note

The compiled `DeepSeek Harness Launcher.app` itself is not checked in — build it locally from source.
