#!/bin/bash
# Build DeepSeek Harness Launcher.app from src/.
# Usage: ./scripts/build.sh [--output PATH]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT=""

while [ $# -gt 0 ]; do
	case "$1" in
		--output)
			OUTPUT="${2:?missing value for --output}"; shift 2;;
		--output=*)
			OUTPUT="${1#--output=}"; shift;;
		-h|--help)
			echo "Usage: ./scripts/build.sh [--output PATH]"; exit 0;;
		*)
			echo "error: unknown arg: $1" >&2; exit 1;;
	esac
done

OUTPUT="${OUTPUT:-$ROOT/build/DeepSeek Harness Launcher.app}"
: "${OUTPUT:?}"
# Never let `rm -rf "$OUTPUT"` below point at a system dir or $HOME.
# Require a .app suffix (blocks /, /tmp, bare dirs) and compare the
# canonical path so symlinks, trailing slashes, and `..` can't bypass it.
stripped="${OUTPUT%/}"
case "$stripped" in
	*.app) ;;
	*)
		echo "error: refusing to build into $OUTPUT (must end in .app)" >&2; exit 1;;
esac
canon="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$stripped" 2>/dev/null || printf '%s' "$stripped")"
case "$canon" in
	"/"|"$HOME"|"/Applications"|"/System"|"/System/"*)
		echo "error: refusing to build into $OUTPUT" >&2; exit 1;;
esac

for tool in /usr/bin/osacompile /usr/libexec/PlistBuddy /usr/bin/codesign /usr/bin/swiftc; do
	if [ ! -x "$tool" ]; then
		echo "error: required tool missing: $tool" >&2; exit 1
	fi
done

mkdir -p "$(dirname "$OUTPUT")"
rm -rf "$OUTPUT"

/usr/bin/osacompile -s -o "$OUTPUT" "$ROOT/src/deepseek-harness-launcher.applescript"

# Embed the checked-in custom icon so fresh builds (and fresh installs)
# carry the whale instead of osacompile's stock script icon. Fail here
# rather than shipping a build with the wrong icon.
if [ ! -f "$ROOT/assets/applet.icns" ]; then
	echo "error: custom icon missing: $ROOT/assets/applet.icns" >&2; exit 1
fi
cp "$ROOT/assets/applet.icns" "$OUTPUT/Contents/Resources/applet.icns"

# Canonical bundle identity lives in assets/bundle-identity (single source
# of truth shared with verify.sh). Fail here rather than shipping a build
# with the wrong identity.
if [ ! -f "$ROOT/assets/bundle-identity" ]; then
	echo "error: bundle identity missing: $ROOT/assets/bundle-identity" >&2; exit 1
fi
# shellcheck disable=SC1091 # sourced data file, not a linted script
. "$ROOT/assets/bundle-identity"

# Set-or-Add a plist key. Survives osacompile template changes if a future
# version ever ships one of these keys itself.
set_or_add() { # set_or_add <type> <key> <value>
	/usr/libexec/PlistBuddy -c "Set :$2 $3" "$OUTPUT/Contents/Info.plist" >/dev/null 2>&1 || \
		/usr/libexec/PlistBuddy -c "Add :$2 $1 $3" "$OUTPUT/Contents/Info.plist"
}

set_or_add string CFBundleDisplayName "$BUNDLE_DISPLAY_NAME"
set_or_add string CFBundleIconFile "$BUNDLE_ICON_FILE"
# CFBundleIconName is untested with this bundle; CFBundleIconFile rules.
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$OUTPUT/Contents/Info.plist" >/dev/null 2>&1 || true
# CFBundleIdentifier is intentionally absent: nothing references one and
# stock osacompile applets carry none. Delete defensively so a future
# template change can't reintroduce it silently.
/usr/libexec/PlistBuddy -c "Delete :CFBundleIdentifier" "$OUTPUT/Contents/Info.plist" >/dev/null 2>&1 || true

# osacompile-built stay-open applets lack LSUIElement (Dock icon); add it so
# the launcher runs without a Dock icon, then re-sign (editing Info.plist
# invalidates the original signature).
set_or_add bool LSUIElement true

# Nested chromeless window (own Dock icon, no browser dependency): compile
# the Swift source straight into a bundle inside Resources, so the launcher
# ships as one install unit. -swift-version 5 dodges Swift 6 mode strictness
# this file does not need.
WINDOW_APP="$OUTPUT/Contents/Resources/DeepSeek Harness.app"
/bin/mkdir -p "$WINDOW_APP/Contents/MacOS" "$WINDOW_APP/Contents/Resources"
/usr/bin/swiftc -swift-version 5 -o "$WINDOW_APP/Contents/MacOS/DeepSeek Harness" "$ROOT/src/window/main.swift" -framework Cocoa -framework WebKit
/bin/cp "$ROOT/src/window/Info.plist" "$WINDOW_APP/Contents/Info.plist"
/bin/cp "$ROOT/assets/applet.icns" "$WINDOW_APP/Contents/Resources/applet.icns"

/usr/bin/codesign --force --deep --sign - "$OUTPUT"

# Fail the build here rather than at install/verify time.
/usr/bin/plutil -lint "$OUTPUT/Contents/Info.plist" >/dev/null
/usr/bin/plutil -lint "$WINDOW_APP/Contents/Info.plist" >/dev/null
/usr/bin/codesign --verify --deep --strict "$OUTPUT"

echo "built: $OUTPUT"
