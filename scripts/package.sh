#!/bin/bash
# Build the single Swift app and a distributable zip. No installer or nested app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/DeepSeek Harness Launcher.app"
ZIP="$ROOT/dist/DeepSeek-Harness-Launcher-macOS.zip"
CHECKSUM="$ZIP.sha256"
VERSION="${1:-0.1.0}"
IDENTITY="${CODESIGN_IDENTITY:--}"
case "$VERSION" in
    *[!0-9.]*|'') echo "error: version must contain only digits and dots" >&2; exit 1 ;;
esac
if [ -n "${NOTARY_PROFILE:-}" ] && [ "$IDENTITY" = '-' ]; then
    echo "error: notarization requires a Developer ID Application signing identity" >&2
    exit 1
fi

mkdir -p "$ROOT/dist"
if [ -e "$CHECKSUM" ]; then rm "$CHECKSUM"; fi
if [ -e "$APP" ]; then rm -R "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

binary_paths=()
for arch in arm64 x86_64; do
    build_args=(--package-path "$ROOT" -c release --triple "$arch-apple-macosx13.0" --scratch-path "$ROOT/.build/$arch")
    swift build "${build_args[@]}" --product DeepSeekHarnessLauncher
    binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
    binary_paths+=("$binary_dir/DeepSeekHarnessLauncher")
done
/usr/bin/lipo -create "${binary_paths[@]}" -output "$APP/Contents/MacOS/DeepSeekHarnessLauncher"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/applet.icns" "$APP/Contents/Resources/applet.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/DeepSeekHarnessLauncher"
sign_args=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != '-' ]; then
    sign_args+=(--options runtime --timestamp)
    if [ -n "${CODESIGN_KEYCHAIN:-}" ]; then sign_args+=(--keychain "$CODESIGN_KEYCHAIN"); fi
fi
/usr/bin/codesign "${sign_args[@]}" "$APP"
/usr/bin/codesign --verify --strict "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/lipo "$APP/Contents/MacOS/DeepSeekHarnessLauncher" -verify_arch arm64
/usr/bin/lipo "$APP/Contents/MacOS/DeepSeekHarnessLauncher" -verify_arch x86_64

if [ -e "$ZIP" ]; then rm "$ZIP"; fi
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    notary_args=(--keychain-profile "$NOTARY_PROFILE")
    if [ -n "${NOTARY_KEYCHAIN:-}" ]; then notary_args+=(--keychain "$NOTARY_KEYCHAIN"); fi
    result="$(xcrun notarytool submit "$ZIP" "${notary_args[@]}" --wait --timeout 30m --output-format json)"
    status="$(printf '%s' "$result" | /usr/bin/plutil -extract status raw -o - -)"
    submission_id="$(printf '%s' "$result" | /usr/bin/plutil -extract id raw -o - -)"
    if [ "$status" != Accepted ]; then
        echo "error: notarization $status (submission $submission_id)" >&2
        exit 1
    fi
    echo "notarization accepted: $submission_id"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    /usr/sbin/spctl --assess --type execute --verbose "$APP"
    rm "$ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
fi

cd "$ROOT/dist"
/usr/bin/shasum -a 256 "$(basename "$ZIP")" > "$(basename "$CHECKSUM")"
echo "packaged: $ZIP"
