#!/bin/bash
# Cover home/path handlers and DSH command selection that
# test_config_parsing.sh does not exercise.
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
ask_noenv() { # ask without the config override (tests live defaults)
	env -u DEEPSEEK_HARNESS_CONFIG /usr/bin/osascript \
		-e "set h to load script POSIX file \"$SCPT\"" -e "tell h to $1"
}

# homeDirectory() has no trailing slash (except root).
check "home-no-trailing-slash" "$HOME" "$(ask_noenv 'homeDirectory()')"
check "workspace-default" "$HOME/.dsh/workspace" "$(ask_noenv 'workspacePath()')"
check "logfile-default" "$HOME/Library/Logs/DeepSeek Harness.log" "$(ask_noenv 'logFilePath()')"

# configFilePath(): override vs live default.
export DEEPSEEK_HARNESS_CONFIG="/tmp/custom.cfg"
check "config-override-exact" "/tmp/custom.cfg" "$(ask 'configFilePath()')"
check "config-default" "$HOME/.config/deepseek-harness-launcher/config" "$(ask_noenv 'configFilePath()')"

# effectiveDshCommand(): default is environment-dependent (Apple Silicon mise,
# Intel mise, PATH mise, npx fallback), but always contains the server args.
unset DEEPSEEK_HARNESS_CONFIG || true
default_cmd="$(ask_noenv 'effectiveDshCommand()')"
case "$default_cmd" in
	*"dsh web --no-open"*) ;;
	*)
		echo "error: default-dsh-command: expected [..dsh web --no-open..], got [$default_cmd]" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
		;;
esac

# DSH_COMMAND override wins verbatim; a leading ~/ is still expanded.
printf '%s\n' 'DSH_COMMAND=echo custom' > "$TMP/dsh.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/dsh.cfg"
check "dsh-override" "echo custom" "$(ask 'effectiveDshCommand()')"
printf '%s\n' 'DSH_COMMAND=~/bin/mydsh web --no-open' > "$TMP/dsh-tilde.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/dsh-tilde.cfg"
check "dsh-tilde-expands" "$HOME/bin/mydsh web --no-open" "$(ask 'effectiveDshCommand()')"

# homeDirectory() honors $HOME (hermetic); falls back to the real home.
check "home-honors-env" "$TMP/fakehome" "$(HOME="$TMP/fakehome" /usr/bin/osascript -e "set h to load script POSIX file \"$SCPT\"" -e 'tell h to homeDirectory()')"
mkdir -p "$TMP/fakehome"
check "workspace-fakehome" "$TMP/fakehome/.dsh/workspace" "$(HOME="$TMP/fakehome" /usr/bin/osascript -e "set h to load script POSIX file \"$SCPT\"" -e 'tell h to workspacePath()')"

# serverCheckURLs(): both loopback families.
check "server-urls" "http://127.0.0.1:3080/, http://[::1]:3080/" "$(ask 'serverCheckURLs("3080")')"

# A process with a different identity must never be signalled after PID reuse.
start_time="$(ask "processStartTime(\"$$\")")"
if [ -z "$start_time" ]; then
	echo "error: process start time was empty for live shell" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
check "process-start-dead" "" "$(ask 'processStartTime("99999999")')"
check "process-start-live" "true" "$(/usr/bin/osascript \
	-e "set h to load script POSIX file \"$SCPT\"" \
	-e "set h's serverPID to \"$$\"" \
	-e "set h's serverStartTime to h's processStartTime(h's serverPID)" \
	-e "return h's processStillOwned()")"
check "process-start-reused" "false" "$(/usr/bin/osascript \
	-e "set h to load script POSIX file \"$SCPT\"" \
	-e "set h's serverPID to \"$$\"" \
	-e "set h's serverStartTime to \"stale\"" \
	-e "return h's processStillOwned()")"

# rotateLogIfNeeded(): small kept, large rotated to .1.
printf 'small' > "$TMP/rot-small.log"
ask "rotateLogIfNeeded(\"$TMP/rot-small.log\")" >/dev/null
test -f "$TMP/rot-small.log" || { echo "error: rotate-small: log missing" >&2; LIB_FAILS=$((LIB_FAILS + 1)); }
test ! -f "$TMP/rot-small.log.1" || { echo "error: rotate-small: unexpected .1" >&2; LIB_FAILS=$((LIB_FAILS + 1)); }
python3 -c "open('$TMP/rot-big.log','wb').write(b'x'*6000000)"
ask "rotateLogIfNeeded(\"$TMP/rot-big.log\")" >/dev/null
test -f "$TMP/rot-big.log.1" || { echo "error: rotate-big: .1 missing" >&2; LIB_FAILS=$((LIB_FAILS + 1)); }

lib_report "handlers ok"
