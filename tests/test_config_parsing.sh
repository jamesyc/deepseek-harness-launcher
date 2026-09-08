#!/bin/bash
# Exercise the AppleScript config handlers against fixture configs.
# Uses the DEEPSEEK_HARNESS_CONFIG test hook (see configFilePath handler).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

need_macos "osacompile/osascript missing"
setup_tmp

SCPT="$TMP/handlers.scpt"
/usr/bin/osacompile -o "$SCPT" "$ROOT/src/deepseek-harness-launcher.applescript"

ask() { # ask '<handler call>' -> prints handler result
	/usr/bin/osascript -e "set h to load script POSIX file \"$SCPT\"" -e "tell h to $1"
}

# Pure handlers (no config needed).
check "unquoted" "/tmp/a b" "$(ask 'unquoted("\"/tmp/a b\"")')"
check "unquoted-plain" "plain" "$(ask 'unquoted("plain")')"
check "expandedPath-tilde" "$HOME/work" "$(ask 'expandedPath("~/work")')"
check "expandedPath-bare" "$HOME" "$(ask 'expandedPath("~")')"
check "expandedPath-abs" "/tmp/x" "$(ask 'expandedPath("/tmp/x")')"

# Full fixture.
export DEEPSEEK_HARNESS_CONFIG="$ROOT/tests/fixtures/config.full"
check "port" "3099" "$(ask 'effectiveServerPort()')"
check "workspace" "$HOME/work/dsh-test" "$(ask 'effectiveWorkspacePath()')"
check "logfile" "/tmp/dsh harness test.log" "$(ask 'effectiveLogFilePath()')"
check "dsh-command" "echo fixture-command" "$(ask 'effectiveDshCommand()')"
check "missing-key" "" "$(ask 'configValueFor("NO_SUCH_KEY")')"

# Invalid port falls back to the default.
printf '%s\n' 'SERVER_PORT=bogus' > "$TMP/bad-port.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/bad-port.cfg"
check "bad-port-fallback" "3080" "$(ask 'effectiveServerPort()')"

# Missing file falls back to defaults.
export DEEPSEEK_HARNESS_CONFIG="$TMP/does-not-exist.cfg"
check "missing-file-port" "3080" "$(ask 'effectiveServerPort()')"
check "missing-file-workspace" "$HOME/.dsh/workspace" "$(ask 'effectiveWorkspacePath()')"

# Existing CHROME_APP dir is used verbatim (no picker).
printf '%s\n' "CHROME_APP=$TMP" > "$TMP/chrome.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/chrome.cfg"
check "chrome-app" "$TMP" "$(ask 'effectiveChromeApp()')"

lib_report "config parsing ok"
