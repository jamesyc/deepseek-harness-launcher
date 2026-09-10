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
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for tool in /usr/bin/plutil /usr/bin/osadecompile /usr/bin/codesign; do
	if [ ! -x "$tool" ]; then
		echo "error: required tool missing: $tool" >&2; exit 1
	fi
done

if [ ! -d "$launcher_app" ]; then
	echo "error: bundle not found at $launcher_app (run ./scripts/build.sh first, or pass the path)" >&2
	exit 1
fi
if [ ! -f "$launcher_app/Contents/Info.plist" ]; then
	echo "error: Info.plist missing in $launcher_app" >&2
	exit 1
fi

/usr/bin/plutil -lint "$launcher_app/Contents/Info.plist" >/dev/null
# plutil prints bools as true/1/YES depending on OS version; accept all truthy forms.
lsui_raw="$(/usr/bin/plutil -extract LSUIElement raw "$launcher_app/Contents/Info.plist" 2>/dev/null || true)"
case "$(printf '%s' "$lsui_raw" | /usr/bin/tr '[:upper:]' '[:lower:]')" in
	true|1|yes) ;;
	*)
		echo "error: LSUIElement is not true (launcher would show a Dock icon)" >&2
		exit 1;;
esac

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

# The icon must match the checked-in source of truth byte-for-byte.
# A mismatch means a stale (pre-whale / pre-16x16) or foreign icon shipped.
reference_icon="$ROOT/assets/applet.icns"
if [ ! -f "$reference_icon" ]; then
	echo "error: reference icon missing at $reference_icon" >&2
	exit 1
fi
if ! cmp -s "$reference_icon" "$launcher_app/Contents/Resources/applet.icns"; then
	echo 'error: applet.icns does not match assets/applet.icns (stale or foreign icon; rebuild via ./scripts/build.sh)' >&2
	exit 1
fi

# Canonical bundle identity from assets/bundle-identity (single source of
# truth shared with build.sh).
if [ ! -f "$ROOT/assets/bundle-identity" ]; then
	echo "error: bundle identity missing at $ROOT/assets/bundle-identity" >&2
	exit 1
fi
# shellcheck disable=SC1091 # sourced data file, not a linted script
. "$ROOT/assets/bundle-identity"

# CFBundleIdentifier must be absent by design (nothing references one).
if /usr/bin/plutil -extract CFBundleIdentifier raw "$launcher_app/Contents/Info.plist" >/dev/null 2>&1; then
	echo 'error: CFBundleIdentifier must be absent (remove it; see assets/bundle-identity)' >&2
	exit 1
fi
display_name="$(/usr/bin/plutil -extract CFBundleDisplayName raw "$launcher_app/Contents/Info.plist" 2>/dev/null || true)"
if [ "$display_name" != "$BUNDLE_DISPLAY_NAME" ]; then
	echo "error: CFBundleDisplayName [$display_name] != [$BUNDLE_DISPLAY_NAME]" >&2
	exit 1
fi
icon_file="$(/usr/bin/plutil -extract CFBundleIconFile raw "$launcher_app/Contents/Info.plist" 2>/dev/null || true)"
if [ "$icon_file" != "$BUNDLE_ICON_FILE" ]; then
	echo "error: CFBundleIconFile [$icon_file] != [$BUNDLE_ICON_FILE]" >&2
	exit 1
fi
# CFBundleIconName must be absent (CFBundleIconFile rules).
if /usr/bin/plutil -extract CFBundleIconName raw "$launcher_app/Contents/Info.plist" >/dev/null 2>&1; then
	echo 'error: CFBundleIconName must be absent (CFBundleIconFile rules)' >&2
	exit 1
fi

if ! /usr/bin/codesign --verify --deep --strict "$launcher_app" 2>/dev/null; then
	echo "error: code signature invalid for $launcher_app" >&2
	exit 1
fi

echo 'launcher bundle verified'
