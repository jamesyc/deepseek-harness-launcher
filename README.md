# DeepSeek Harness Launcher for macOS

A single native Swift app for `dsh web`. It opens the Harness in WebKit, supports multiple windows, and manages the server only when it started that server itself.

## Requirements

- macOS 13 or newer.
- An installed `dsh` executable. The app never downloads or installs it. If it cannot find `dsh`, it shows an error and opens Settings so you can select the executable.

## Get the app

Download `DeepSeek-Harness-Launcher-macOS.zip` from the latest GitHub release, unzip it, and drag `DeepSeek Harness Launcher.app` to Applications. There is no installer script. The release archive contains one universal app for Apple Silicon and Intel Macs.

Version-tag releases are Developer ID signed and notarized when the `release` GitHub environment has its signing and notary secrets configured. Pull-request artifacts use ad hoc signing for tests. See [release setup](docs/RELEASING.md).

## What happens at launch

1. The app looks for `dsh` on common executable paths or through `mise which dsh`. A path selected in Settings takes precedence. A mise-resolved `dsh` runs through `mise exec` so its runtime is on `PATH`; automatic tool installation is disabled. If no executable exists, the app displays an error.
2. It checks for a running `dsh web` listener. If one responds, the app attaches to it and **does not stop it** when the app quits. A token-protected server can be attached when its startup URL is available from its open log, or from a URL saved in Settings. If a terminal-started server hides its token URL, paste the URL printed by `dsh web` into Settings.
3. If no `dsh web` server is running, the app launches the installed executable with `web --no-open --port 0`. It reads the startup URL, waits for HTTP readiness, and opens it in WebKit. When the last Harness window closes or you choose Quit, it stops only this child process.

The app uses the existing WebKit bundle identifier (`local.deepseek-harness.window`) to keep the same website data store. File > New Window (⌘N) opens another view of the same server. The server stays alive until the last Harness window closes. External links open in the default browser; downloads go to Downloads.

## Settings

Open **DeepSeek Harness → Settings…** (⌘,) to set:

| Setting | Purpose |
| --- | --- |
| dsh executable | Optional path to an already installed `dsh`; leave empty to find it automatically. |
| Workspace | Directory used when this app starts a new server; defaults to `~/.dsh/workspace`. |
| Existing server URL | Optional loopback URL, including the token when required, for an already running server. Stored in macOS Keychain. |

Settings are managed in the app. The old `~/.config/deepseek-harness-launcher/config` file and `DSH_COMMAND`, `SERVER_PORT`, `WORKSPACE`, and `LOG_FILE` shell settings are no longer read. If you used them, open the Settings window and select your executable and workspace. The app no longer keeps a token-bearing server log.

## Build and test

Xcode's Swift toolchain is required to build. No package dependencies are downloaded.

```sh
swift test
./tests/test_package.sh
```

`scripts/package.sh [version]` builds both macOS architectures, combines them into one `.app`, signs it, verifies its bundle, and creates the zip and SHA-256 file in `dist/`. Set `CODESIGN_IDENTITY` to a Developer ID identity for hardened-runtime signing. Add `NOTARY_PROFILE=tcapsulesmb-notary` to notarize locally with your existing Keychain profile; the script staples the ticket before making the final zip.

GitHub Actions runs Swift tests and the package test for pull requests and `main`. Pushing a `v*` tag builds, signs, notarizes, and publishes a versioned archive. The release job requires `contents: write` only for that tag job.

## Troubleshooting

- **dsh not found:** Install `dsh`, then reopen the app or choose its executable in Settings.
- **Running server needs its token:** Paste the full local URL printed by that server into Settings. The app will verify it before attaching.
- **Server did not start:** Check that `dsh web --no-open --port 0` works in your terminal and that your workspace directory is writable. Startup errors appear in the app without exposing token values.
