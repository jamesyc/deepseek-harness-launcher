#!/bin/bash
# Build the single Swift app and a distributable zip. No installer or nested app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/DeepSeek Harness Launcher.app"
ZIP="$ROOT/dist/DeepSeek-Harness-Launcher-macOS.zip"
VERSION="${1:-0.1.0}"
case "$VERSION" in
    *[!0-9.]*|'') echo "error: version must contain only digits and dots" >&2; exit 1 ;;
esac

mkdir -p "$ROOT/dist"
if [ -e "$APP" ]; then rm -R "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
    swift build --package-path "$ROOT" -c release --triple "$arch-apple-macosx13.0" \
        --scratch-path "$ROOT/.build/$arch" --product DeepSeekHarnessLauncher
done
/usr/bin/lipo -create \
    "$ROOT/.build/arm64/out/Products/Release/DeepSeekHarnessLauncher" \
    "$ROOT/.build/x86_64/out/Products/Release/DeepSeekHarnessLauncher" \
    -output "$APP/Contents/MacOS/DeepSeekHarnessLauncher"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/applet.icns" "$APP/Contents/Resources/applet.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/DeepSeekHarnessLauncher"
/usr/bin/codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/lipo -verify_arch arm64 "$APP/Contents/MacOS/DeepSeekHarnessLauncher"
/usr/bin/lipo -verify_arch x86_64 "$APP/Contents/MacOS/DeepSeekHarnessLauncher"

if [ -e "$ZIP" ]; then rm "$ZIP"; fi
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
cd "$ROOT/dist"
/usr/bin/shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256"
echo "packaged: $ZIP"
