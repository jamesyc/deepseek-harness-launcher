#!/bin/bash
# Smoke-test a built DeepSeek Harness Launcher.app bundle.
# Usage: ./scripts/verify.sh [launcher_app_path]
# Env override: DEEPSEEK_HARNESS_LAUNCHER_APP=/path/to/Launcher.app
set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	echo "Usage: ./scripts/verify.sh [launcher_app_path]"
	exit 0
fi

# Usage: ./scripts/verify.sh [launcher_app_path]
# Env override: DEEPSEEK_HARNESS_LAUNCHER_APP=/path/to/Launcher.app
launcher_app="${1:-${DEEPSEEK_HARNESS_LAUNCHER_APP:-$HOME/Applications/DeepSeek Harness Launcher.app}}"

if [ ! -d "$launcher_app" ]; then
	echo "error: bundle not found at $launcher_app (run ./scripts/build.sh first, or pass the path)" >&2
	exit 1
fi
if [ ! -f "$launcher_app/Contents/Info.plist" ]; then
	echo "error: Info.plist missing in $launcher_app" >&2
	exit 1
fi

/usr/bin/plutil -lint "$launcher_app/Contents/Info.plist" >/dev/null
if [ "$(/usr/bin/plutil -extract LSUIElement raw "$launcher_app/Contents/Info.plist" 2>/dev/null)" != "true" ]; then
	echo "error: LSUIElement is not true (launcher would show a Dock icon)" >&2
	exit 1
fi

# Decompile once to a file; never pipe the producer into grep -q (SIGPIPE
# under pipefail misfires — see tests/test_no_pipe_grep.sh).
decompiled="$(mktemp)"
trap 'rm -f "$decompiled"' EXIT
/usr/bin/osadecompile "$launcher_app" > "$decompiled"

for pattern in 'dsh web --no-open' 'kill -TERM' 'DeepSeek Harness.app'; do
	if ! grep -q "$pattern" "$decompiled"; then
		echo "error: expected string [$pattern] not found in launcher script" >&2
		exit 1
	fi
done

# No hardcoded usernames may ship in the published source.
if grep -q '/Users/' "$decompiled"; then
	echo 'error: launcher still contains hardcoded /Users/ path' >&2
	exit 1
fi

if [ ! -f "$launcher_app/Contents/Resources/applet.icns" ]; then
	echo "error: applet.icns missing in $launcher_app" >&2
	exit 1
fi

if ! /usr/bin/codesign --verify --deep "$launcher_app" 2>/dev/null; then
	echo "error: code signature invalid for $launcher_app" >&2
	exit 1
fi

echo 'launcher bundle verified'
