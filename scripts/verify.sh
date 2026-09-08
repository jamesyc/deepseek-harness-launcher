#!/bin/bash
set -euo pipefail

# Usage: ./scripts/verify.sh [launcher_app_path]
# Env override: DEEPSEEK_HARNESS_LAUNCHER_APP=/path/to/Launcher.app
launcher_app="${1:-${DEEPSEEK_HARNESS_LAUNCHER_APP:-$HOME/Applications/DeepSeek Harness Launcher.app}}"

test -d "$launcher_app"
plutil -lint "$launcher_app/Contents/Info.plist"
test "$(plutil -extract LSUIElement raw "$launcher_app/Contents/Info.plist")" = true

# Decompile once into a file and grep the file. Never `osadecompile |
# grep -q` here: under pipefail, grep -q exits on first match, osadecompile
# then dies on SIGPIPE, and pipefail + set -e fails a bundle that matched.
decompiled="$(mktemp)"
trap 'rm -f "$decompiled"' EXIT
osadecompile "$launcher_app" > "$decompiled"
grep -q 'dsh web --no-open' "$decompiled"
grep -q 'kill -TERM' "$decompiled"
grep -q 'DeepSeek Harness.app' "$decompiled"

# No hardcoded usernames may ship in the published source.
if grep -q '/Users/' "$decompiled"; then
	echo 'error: launcher still contains hardcoded /Users/ path' >&2
	grep -n '/Users/' "$decompiled" >&2 || true
	exit 1
fi

test -f "$launcher_app/Contents/Resources/applet.icns"

echo 'launcher bundle verified'
