# Refactor verification checklist

- [x] Replace AppleScript runtime with a single Swift executable and native WebKit windows.
- [x] Add a native Settings window with persisted executable/workspace values and a Keychain-backed server URL.
- [x] Start an installed `dsh` when none is running; surface a missing executable as an error.
- [x] Attach to an existing server and leave it running when the app exits.
- [x] Support multiple windows sharing one server.
- [x] Replace build/install/verify scripts with a universal app zip package and GitHub CI release workflow.
- [x] Replace source-text tests with process, HTTP, AppKit, settings, and package tests.
- [x] Verify an actual packaged app attaches to an existing token server and leaves it alive after last-window close.
- [x] Verify owned start and stop with a real fake `dsh` child and loopback HTTP integration tests.
- [x] Run the full Swift suite, shell lint, and package gate after final cleanup.
