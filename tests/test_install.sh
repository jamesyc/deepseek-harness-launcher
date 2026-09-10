#!/bin/bash
# scripts/install.sh: fresh install, full-copy update, backup, and errors.
# Everything runs under $TMP via --from/--to; never touches ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"
# shellcheck disable=SC1091 # sourced data file, not a linted script
. "$ROOT/assets/bundle-identity"

need_macos "osacompile missing"
setup_tmp

expect_fail() { # expect_fail <label> <command...>
	if "$@" >/dev/null 2>&1; then
		echo "error: $1: expected failure, got success" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}

# --help exits 0 and mentions usage; unknown args are rejected.
"$ROOT/scripts/install.sh" --help >"$TMP/help.txt" 2>/dev/null
assert_file_contains "$TMP/help.txt" 'Usage:' "install-help"
expect_fail "install-unknown-arg" "$ROOT/scripts/install.sh" --bogus

# Missing FROM fails with a actionable message.
if "$ROOT/scripts/install.sh" --from "$TMP/nope.app" --to "$TMP/x.app" 2>"$TMP/missing-err.txt"; then
	echo "error: install-missing-from: expected failure, got success" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
elif ! grep -q 'run ./scripts/build.sh first' "$TMP/missing-err.txt"; then
	echo "error: install-missing-from: wrong error message" >&2
	cat "$TMP/missing-err.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
fi

# Fresh install: TO missing -> full copy that verifies.
"$ROOT/scripts/build.sh" --output "$TMP/from.app" >/dev/null
if ! "$ROOT/scripts/install.sh" --from "$TMP/from.app" --to "$TMP/to.app" >"$TMP/fresh-out.txt" 2>&1; then
	echo "error: install-fresh: command failed" >&2
	cat "$TMP/fresh-out.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
elif ! grep -q 'fresh install' "$TMP/fresh-out.txt"; then
	echo "error: install-fresh: expected 'fresh install' message" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
test -f "$TMP/to.app/Contents/Resources/Scripts/main.scpt" || {
	echo "error: install-fresh: main.scpt missing in TO" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
}

# Update: pre-seed TO with a sentinel plist key, a rogue identifier, a wrong
# display name, and stale main.scpt/icon, so the test proves the full copy
# replaces everything (stale state gone, FROM state present).
# NOTE: osacompile applets carry no CFBundleIdentifier, so use a custom key.
/usr/libexec/PlistBuddy -c "Add :SentinelPreserved string yes" \
	"$TMP/to.app/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.example.stale" \
	"$TMP/to.app/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Delete :CFBundleDisplayName" \
	"$TMP/to.app/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Stale Name" \
	"$TMP/to.app/Contents/Info.plist" >/dev/null
/usr/bin/osacompile -o "$TMP/to.app/Contents/Resources/Scripts/main.scpt" \
	-e 'display dialog "old"' >/dev/null
# Seed a stale icon too, so the test proves applet.icns is replaced
# (not silently preserved).
printf 'stale-icon' > "$TMP/to.app/Contents/Resources/applet.icns"
/usr/bin/codesign --force --deep --sign - "$TMP/to.app" >/dev/null 2>&1

export TMPDIR="$TMP/tmpdir"
mkdir -p "$TMPDIR"
if ! "$ROOT/scripts/install.sh" --from "$TMP/from.app" --to "$TMP/to.app" >"$TMP/update-out.txt" 2>&1; then
	echo "error: install-update: command failed" >&2
	cat "$TMP/update-out.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
else
	grep -q 'backed up existing app' "$TMP/update-out.txt" || {
		echo "error: install-update: expected backup message" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	}
	grep -q 'updated existing app at:' "$TMP/update-out.txt" || {
		echo "error: install-update: expected updated message" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	}
fi

# Stale sentinel plist key is gone after the full copy...
if /usr/libexec/PlistBuddy -c "Print :SentinelPreserved" "$TMP/to.app/Contents/Info.plist" >/dev/null 2>&1; then
	echo "error: install-update: stale sentinel plist key survived (expected full replacement)" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
# ...the rogue identifier is gone...
if /usr/bin/plutil -extract CFBundleIdentifier raw "$TMP/to.app/Contents/Info.plist" >/dev/null 2>&1; then
	echo "error: install-update: stale CFBundleIdentifier survived (expected full replacement)" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
# ...and the display name now matches the canonical identity.
check "install-update-display-name" "$BUNDLE_DISPLAY_NAME" \
	"$(/usr/bin/plutil -extract CFBundleDisplayName raw "$TMP/to.app/Contents/Info.plist" 2>/dev/null || true)"
# ...and main.scpt now matches FROM byte-for-byte...
if ! cmp -s "$TMP/from.app/Contents/Resources/Scripts/main.scpt" \
	"$TMP/to.app/Contents/Resources/Scripts/main.scpt"; then
	echo "error: install-update: main.scpt does not match FROM" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
# ...and applet.icns now matches FROM byte-for-byte...
if ! cmp -s "$TMP/from.app/Contents/Resources/applet.icns" \
	"$TMP/to.app/Contents/Resources/applet.icns"; then
	echo "error: install-update: applet.icns does not match FROM" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
# ...and a backup bundle was left in TMPDIR.
if ! ls -d "$TMPDIR"/DeepSeek-Harness-Launcher-backup-*.app >/dev/null 2>&1; then
	echo "error: install-update: no backup bundle in TMPDIR" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
# Updated TO still verifies and carries a valid signature.
"$ROOT/scripts/verify.sh" "$TMP/to.app" >/dev/null || {
	echo "error: install-update: updated TO fails verify" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
}

# Update no longer resets the picker cache: it lives outside the bundle
# (~/Library/Application Support/...), so no reset note is printed.
cp -R "$TMP/from.app" "$TMP/cacheto.app"
sed 's|^property resolvedChromeAppPath : ""|property resolvedChromeAppPath : "/tmp/cached-choice"|' \
	"$ROOT/src/deepseek-harness-launcher.applescript" > "$TMP/cache.applescript"
/usr/bin/osacompile -o "$TMP/cacheto.app/Contents/Resources/Scripts/main.scpt" \
	"$TMP/cache.applescript" >/dev/null
/usr/bin/codesign --force --deep --sign - "$TMP/cacheto.app" >/dev/null 2>&1
if ! "$ROOT/scripts/install.sh" --from "$TMP/from.app" --to "$TMP/cacheto.app" >"$TMP/cache-out.txt" 2>&1; then
	echo "error: install-cache-update: command failed" >&2
	cat "$TMP/cache-out.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
else
	if grep -q 'file-picker choice was reset' "$TMP/cache-out.txt"; then
		echo "error: install-cache-update: unexpected picker-reset note (cache now lives outside bundle)" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
fi

lib_report "install ok"
