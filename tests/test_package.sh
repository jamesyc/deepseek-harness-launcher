#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VERSION="${1:-0.2.3}"
"$ROOT/scripts/package.sh" "$VERSION"
APP="$ROOT/dist/DeepSeek Harness Launcher.app"
ZIP="$ROOT/dist/DeepSeek-Harness-Launcher-macOS.zip"
test -x "$APP/Contents/MacOS/DeepSeekHarnessLauncher"
test ! -e "$APP/Contents/Resources/DeepSeek Harness.app"
test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" = "$VERSION"
test "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = local.deepseek-harness.window
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/lipo "$APP/Contents/MacOS/DeepSeekHarnessLauncher" -verify_arch arm64
/usr/bin/lipo "$APP/Contents/MacOS/DeepSeekHarnessLauncher" -verify_arch x86_64
if [ "${CODESIGN_IDENTITY:--}" != '-' ]; then
    signature="$(/usr/bin/codesign --display --verbose=4 "$APP" 2>&1)"
    [[ "$signature" == *'(runtime)'* ]]
    [[ "$signature" == *'TeamIdentifier=M22Z394H44'* ]]
    [[ "$signature" == *'Timestamp='* ]]
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun stapler validate "$APP"
    /usr/sbin/spctl --assess --type execute "$APP"
fi

STAGE="$(mktemp -d)"
trap 'rm -R "$STAGE"' EXIT
/usr/bin/ditto -x -k "$ZIP" "$STAGE"
cmp "$APP/Contents/MacOS/DeepSeekHarnessLauncher" \
    "$STAGE/DeepSeek Harness Launcher.app/Contents/MacOS/DeepSeekHarnessLauncher"
cd "$ROOT/dist"
/usr/bin/shasum -a 256 -c "$(basename "$ZIP").sha256"
echo "package verified"
