#!/bin/bash
# chromePidForLoader (src) must match the loader executable exactly:
# equal or followed by a space (args). A substring match would confuse
# /Foo.app/... with /Foo2.app/.... Runs anywhere (pure shell).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

# Parity: if the src matcher changes, update this test.
if ! grep -F -q 'cmd == target' "$ROOT/src/deepseek-harness-launcher.applescript"; then
	echo "error: chrome pid matcher in src drifted; update $0" >&2
	exit 1
fi

LOADER="/Applications/DeepSeek Harness.app/Contents/MacOS/app_mode_loader"
match() { # match <ps line> -> prints pid or empty
	printf '%s\n' "$1" | /usr/bin/awk -v target="$LOADER" '{ pid = $1; sub(/^ *[^ ]+ +/, ""); cmd = $0; if (cmd == target || substr(cmd, 1, length(target) + 1) == target " ") { print pid; exit } }' || true
}

check "loader-with-args" "1234" "$(match ' 1234 /Applications/DeepSeek Harness.app/Contents/MacOS/app_mode_loader --app=http://127.0.0.1:3080')"
check "loader-bare" "9999" "$(match ' 9999 /Applications/DeepSeek Harness.app/Contents/MacOS/app_mode_loader')"
check "reject-suffix-app" "" "$(match ' 5678 /Applications/DeepSeek Harness2.app/Contents/MacOS/app_mode_loader --app=x')"
check "reject-prefix-chars" "" "$(match ' 1111 /Applications/XDeepSeek Harness.app/Contents/MacOS/app_mode_loader')"
check "reject-other-proc" "" "$(match ' 2222 /usr/bin/python server.py')"
check "reject-unrelated-loader" "" "$(match ' 3333 /Applications/Other.app/Contents/MacOS/app_mode_loader --app=y')"

lib_report "chrome pid match ok"
