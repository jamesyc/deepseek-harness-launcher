#!/bin/bash
set -euo pipefail

# Usage: ./scripts/verify.sh [launcher_app_path]
# Env override: DEEPSEEK_HARNESS_LAUNCHER_APP=/path/to/Launcher.app
launcher_app="${1:-${DEEPSEEK_HARNESS_LAUNCHER_APP:-$HOME/Applications/DeepSeek Harness Launcher.app}}"

test -d "$launcher_app"
plutil -lint "$launcher_app/Contents/Info.plist"
test "$(plutil -extract LSUIElement raw "$launcher_app/Contents/Info.plist")" = true
osadecompile "$launcher_app" | grep -q 'dsh web --no-open'
osadecompile "$launcher_app" | grep -q 'kill -TERM'
osadecompile "$launcher_app" | grep -q 'DeepSeek Harness.app'

# No hardcoded usernames may ship in the published source.
if osadecompile "$launcher_app" | grep -q '/Users/'; then
	echo 'error: launcher still contains hardcoded /Users/ path' >&2
	exit 1
fi

test -f "$launcher_app/Contents/Resources/applet.icns"

echo 'launcher bundle verified'
