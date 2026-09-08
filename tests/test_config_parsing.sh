#!/bin/bash
# Exercise the AppleScript config handlers against fixture configs.
# Uses the DEEPSEEK_HARNESS_CONFIG test hook (see configFilePath handler).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
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
check "unquoted-empty-quotes-is-empty" "" "$(ask 'unquoted("\"\"")')"
check "unquoted-single-char" '"' "$(ask 'unquoted("\"")')"
check "unquoted-empty" "" "$(ask 'unquoted("")')"
check "expandedPath-tilde" "$HOME/work" "$(ask 'expandedPath("~/work")')"
check "expandedPath-bare" "$HOME" "$(ask 'expandedPath("~")')"
check "expandedPath-tilde-slash" "$HOME/" "$(ask 'expandedPath("~/")')"
check "expandedPath-abs" "/tmp/x" "$(ask 'expandedPath("/tmp/x")')"
check "expandedPath-otheruser-passthrough" "~otheruser/x" "$(ask 'expandedPath("~otheruser/x")')"
check "expandedPath-relative-passthrough" "work/foo" "$(ask 'expandedPath("work/foo")')"
check "expandedPath-empty" "" "$(ask 'expandedPath("")')"

# Full fixture.
export DEEPSEEK_HARNESS_CONFIG="$ROOT/tests/fixtures/config.full"
check "port" "3099" "$(ask 'effectiveServerPort()')"
check "workspace" "$HOME/work/dsh-test" "$(ask 'effectiveWorkspacePath()')"
check "logfile" "/tmp/dsh harness test.log" "$(ask 'effectiveLogFilePath()')"
check "dsh-command" "echo fixture-command" "$(ask 'effectiveDshCommand()')"
check "missing-key" "" "$(ask 'configValueFor("NO_SUCH_KEY")')"

# Last occurrence wins; values may contain '='.
export DEEPSEEK_HARNESS_CONFIG="$ROOT/tests/fixtures/config.dup-equals"
check "last-wins" "2222" "$(ask 'effectiveServerPort()')"
check "equals-in-value" "echo a=b=c" "$(ask 'effectiveDshCommand()')"

# '#' comment lines are ignored.
export DEEPSEEK_HARNESS_CONFIG="$ROOT/tests/fixtures/config.comments"
check "comment-ignored" "3101" "$(ask 'effectiveServerPort()')"

# Trailing comments are NOT stripped: value becomes invalid -> default port.
printf '%s\n' 'SERVER_PORT=3099 # comment' > "$TMP/trailing.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/trailing.cfg"
check "trailing-comment-fallback" "3080" "$(ask 'effectiveServerPort()')"

# Keys with surrounding spaces do not match ('^KEY='): falls back.
printf '%s\n' 'SERVER_PORT = 3099' > "$TMP/spaced.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/spaced.cfg"
check "spaced-key-fallback" "3080" "$(ask 'effectiveServerPort()')"

# Port boundaries and whitespace.
probe_port() { # probe_port <file content> <label> <expected>
	printf '%s\n' "$1" > "$TMP/probe.cfg"
	export DEEPSEEK_HARNESS_CONFIG="$TMP/probe.cfg"
	check "$2" "$3" "$(ask 'effectiveServerPort()')"
}
probe_port 'SERVER_PORT=0' "port-0-fallback" "3080"
probe_port 'SERVER_PORT=-1' "port-negative-fallback" "3080"
probe_port 'SERVER_PORT=65536' "port-65536-fallback" "3080"
probe_port 'SERVER_PORT=99999' "port-99999-fallback" "3080"
probe_port 'SERVER_PORT=bogus' "port-bogus-fallback" "3080"
probe_port 'SERVER_PORT=' "port-empty-fallback" "3080"
probe_port 'SERVER_PORT=1' "port-1-ok" "1"
probe_port 'SERVER_PORT=65535' "port-65535-ok" "65535"
probe_port 'SERVER_PORT=03099' "port-leading-zero" "3099"
probe_port 'SERVER_PORT= 3099 ' "port-whitespace-trimmed" "3099"

# Empty WORKSPACE falls back to the default.
printf '%s\n' 'WORKSPACE=' > "$TMP/empty-ws.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/empty-ws.cfg"
check "empty-workspace-fallback" "$HOME/.dsh/workspace" "$(ask 'effectiveWorkspacePath()')"

# Single quotes are NOT stripped (only surrounding double quotes are).
printf '%s\n' "DSH_COMMAND='echo hi'" > "$TMP/single.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/single.cfg"
check "single-quotes-kept" "'echo hi'" "$(ask 'effectiveDshCommand()')"

# Empty quoted values count as unset and fall back to defaults.
printf '%s\n' 'WORKSPACE=""' > "$TMP/quoted-empty.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/quoted-empty.cfg"
check "quoted-empty-workspace-fallback" "$HOME/.dsh/workspace" "$(ask 'effectiveWorkspacePath()')"
printf '%s\n' 'LOG_FILE=""' > "$TMP/quoted-empty-log.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/quoted-empty-log.cfg"
check "quoted-empty-logfile-fallback" "$HOME/Library/Logs/DeepSeek Harness.log" "$(ask 'effectiveLogFilePath()')"
printf '%s\n' 'SERVER_PORT=""' > "$TMP/quoted-empty-port.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/quoted-empty-port.cfg"
check "quoted-empty-port-fallback" "3080" "$(ask 'effectiveServerPort()')"
export DEEPSEEK_HARNESS_CONFIG="$TMP/does-not-exist.cfg"
default_dsh="$(ask 'effectiveDshCommand()')"
printf '%s\n' 'DSH_COMMAND=""' > "$TMP/quoted-empty-dsh.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/quoted-empty-dsh.cfg"
check "quoted-empty-dsh-fallback" "$default_dsh" "$(ask 'effectiveDshCommand()')"

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
