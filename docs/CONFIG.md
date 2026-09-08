# Configuration reference

All settings have working defaults — no config file needed. To override, create
`~/.config/deepseek-harness-launcher/config` as plain `KEY=value` lines.
A commented template lives at `examples/config.example`.

## Format

- One `KEY=value` per line; `#` starts a comment.
- Last occurrence of a key wins.
- A leading `~/` in a value is expanded to your home folder.
- Surrounding double quotes are stripped (useful for values with spaces).
- Values may contain `=` (only the first `=` separates key from value).

```sh
# ~/.config/deepseek-harness-launcher/config
SERVER_PORT=3080
WORKSPACE=~/.dsh/workspace
LOG_FILE=~/Library/Logs/DeepSeek Harness.log
CHROME_APP=~/Applications/Chrome Apps.localized/DeepSeek Harness.app
# DSH_COMMAND=npx -y @deepseek-ai/dsh web --no-open
```

## Keys

| Key | Overrides | Default | Notes |
|---|---|---|---|
| `SERVER_PORT` | `serverPort` property | `3080` | Must be 1–65535; invalid values fall back silently |
| `WORKSPACE` | `~/.dsh/workspace` | Home-resolved default | Created with `mkdir -p` on first run |
| `LOG_FILE` | `~/Library/Logs/DeepSeek Harness.log` | Home-resolved default | Truncated each time the launcher starts its own server, then appended |
| `CHROME_APP` | auto-search + file picker | — | If set but missing, a notice shows and search proceeds |
| `DSH_COMMAND` | auto-detected `mise`/`npx` command | `mise` → `npx` fallback chain | Used verbatim; no `~/` expansion needed |

## Precedence

config file → built-in defaults. The file-picker cache
(`resolvedChromeAppPath` property) is only consulted when `CHROME_APP` is unset.

For build-time defaults (used when no config file exists), edit the `property`
lines at the top of `src/deepseek-harness-launcher.applescript` and rebuild.

## Testing override

Set `DEEPSEEK_HARNESS_CONFIG` to point the launcher at a different config file
instead of `~/.config/...`. Used by `tests/test_config_parsing.sh`; handy for
trying settings without touching your live config:

```sh
DEEPSEEK_HARNESS_CONFIG=/tmp/test.cfg open ~/Applications/"DeepSeek Harness Launcher.app"
```

Note: GUI apps launched from Finder don't inherit your shell's environment, so
this override mainly takes effect when launching from a terminal (or from tests).
