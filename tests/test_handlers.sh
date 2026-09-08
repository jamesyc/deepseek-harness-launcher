#!/bin/bash
# Cover home/path handlers, chrome loader resolution, and DSH command
# selection that test_config_parsing.sh does not exercise.
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
ask_noenv() { # ask without the config/cache overrides (tests live defaults)
	env -u DEEPSEEK_HARNESS_CONFIG -u DEEPSEEK_HARNESS_CACHE /usr/bin/osascript \
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

# chromeLoaderPathFor(): reads CFBundleExecutable, falls back to app_mode_loader.
mkdir -p "$TMP/Fake.app/Contents/MacOS"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string CustomLoader" "$TMP/Fake.app/Contents/Info.plist" >/dev/null
touch "$TMP/Fake.app/Contents/MacOS/CustomLoader"
check "loader-from-plist" "$TMP/Fake.app/Contents/MacOS/CustomLoader" "$(ask "chromeLoaderPathFor(\"$TMP/Fake.app\")")"

mkdir -p "$TMP/Plain.app/Contents/MacOS"
check "loader-fallback" "$TMP/Plain.app/Contents/MacOS/app_mode_loader" "$(ask "chromeLoaderPathFor(\"$TMP/Plain.app\")")"

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

# CHROME_APP with ~/ expands to $HOME. Uses a dotfile under $HOME with trap
# cleanup so failures don't leave residue.
HOME_TMP_APP="$HOME/.tmp-chrome-handler-test.app"
rm -rf "$HOME_TMP_APP"
mkdir -p "$HOME_TMP_APP"
trap 'rm -rf "$HOME_TMP_APP" "$TMP"' EXIT
printf '%s\n' 'CHROME_APP=~/.tmp-chrome-handler-test.app' > "$TMP/chrome-tilde.cfg"
export DEEPSEEK_HARNESS_CONFIG="$TMP/chrome-tilde.cfg"
check "chrome-tilde-expands" "$HOME/.tmp-chrome-handler-test.app" "$(ask 'effectiveChromeApp()')"
rm -rf "$HOME_TMP_APP"
trap 'rm -rf "$TMP"' EXIT

# chromeCacheFile(): override vs live default.
export DEEPSEEK_HARNESS_CACHE="$TMP/chrome-cache.txt"
check "cache-override-exact" "$TMP/chrome-cache.txt" "$(ask 'chromeCacheFile()')"
check "cache-default" "$HOME/Library/Application Support/DeepSeek Harness Launcher/ChromeAppPath" "$(env -u DEEPSEEK_HARNESS_CACHE /usr/bin/osascript -e "set h to load script POSIX file \"$SCPT\"" -e 'tell h to chromeCacheFile()')"

# write/read round-trip (600 perms) + findChromeApp prefers the file cache.
mkdir -p "$TMP/Cached.app"
export DEEPSEEK_HARNESS_CACHE="$TMP/chrome-cache.txt"
ask "writeChromeCache(\"$TMP/Cached.app\")" >/dev/null
check "cache-roundtrip" "$TMP/Cached.app" "$(ask 'readChromeCache()')"
check "find-prefers-cache" "$TMP/Cached.app" "$(ask 'findChromeApp()')"
if [ "$(stat -f %A "$TMP/chrome-cache.txt")" != "600" ]; then
	echo "error: cache-perms: expected 600" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi

# serverCheckURLs(): both loopback families.
check "server-urls" "http://127.0.0.1:3080/, http://[::1]:3080/" "$(ask 'serverCheckURLs("3080")')"

# rotateLogIfNeeded(): small kept, large rotated to .1.
printf 'small' > "$TMP/rot-small.log"
ask "rotateLogIfNeeded(\"$TMP/rot-small.log\")" >/dev/null
test -f "$TMP/rot-small.log" || { echo "error: rotate-small: log missing" >&2; LIB_FAILS=$((LIB_FAILS + 1)); }
test ! -f "$TMP/rot-small.log.1" || { echo "error: rotate-small: unexpected .1" >&2; LIB_FAILS=$((LIB_FAILS + 1)); }
python3 -c "open('$TMP/rot-big.log','wb').write(b'x'*6000000)"
ask "rotateLogIfNeeded(\"$TMP/rot-big.log\")" >/dev/null
test -f "$TMP/rot-big.log.1" || { echo "error: rotate-big: .1 missing" >&2; LIB_FAILS=$((LIB_FAILS + 1)); }

# chromePidForLoader(): runs against live ps; just assert it exits 0 and prints PID-or-empty.
ask "chromePidForLoader(\"$TMP/Cached.app/Contents/MacOS/app_mode_loader\")" >/dev/null || {
	echo "error: chrome-pid-handler failed" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
}

lib_report "handlers ok"
