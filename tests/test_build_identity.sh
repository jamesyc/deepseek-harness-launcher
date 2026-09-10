#!/bin/bash
# scripts/build.sh stamps canonical bundle identity from
# assets/bundle-identity: no CFBundleIdentifier, pinned display name and
# icon file, no CFBundleIconName.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"
# shellcheck disable=SC1091 # sourced data file, not a linted script
. "$ROOT/assets/bundle-identity"

need_macos "osacompile missing"
setup_tmp

"$ROOT/scripts/build.sh" --output "$TMP/id.app" >/dev/null
plist="$TMP/id.app/Contents/Info.plist"

# CFBundleIdentifier must be absent by design.
if /usr/bin/plutil -extract CFBundleIdentifier raw "$plist" >/dev/null 2>&1; then
	echo "error: build-identifier-absent: CFBundleIdentifier present" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
check "build-display-name" "$BUNDLE_DISPLAY_NAME" \
	"$(/usr/bin/plutil -extract CFBundleDisplayName raw "$plist" 2>/dev/null || true)"
check "build-icon-file" "$BUNDLE_ICON_FILE" \
	"$(/usr/bin/plutil -extract CFBundleIconFile raw "$plist" 2>/dev/null || true)"
# CFBundleIconName must be absent (CFBundleIconFile rules).
if /usr/bin/plutil -extract CFBundleIconName raw "$plist" >/dev/null 2>&1; then
	echo "error: build-iconname-absent: CFBundleIconName present" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi

lib_report "build identity ok"
