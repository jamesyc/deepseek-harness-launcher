#!/bin/bash
# scripts/install.sh: fresh install, update transplant, backup, and errors.
# Everything runs under $TMP via --from/--to; never touches ~/Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

need_macos "osacompile missing"
setup_tmp

expect_fail() { # expect_fail <label> <command...>
	if "$@" >/dev/null 2>&1; then
		echo "error: $1: expected failure, got success" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}

# --help exits 0; unknown args are rejected.
if ! "$ROOT/scripts/install.sh" --help 2>/dev/null | grep -q 'Usage:'; then
	echo "error: install-help: expected usage text" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
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

# Update: pre-seed TO with a sentinel plist key + stale main.scpt, so the
# test proves only main.scpt is transplanted (bundle ID/icon/plist kept).
# NOTE: osacompile applets carry no CFBundleIdentifier, so use a custom key.
/usr/libexec/PlistBuddy -c "Add :SentinelPreserved string yes" \
	"$TMP/to.app/Contents/Info.plist" >/dev/null
/usr/bin/osacompile -o "$TMP/to.app/Contents/Resources/Scripts/main.scpt" \
	-e 'display dialog "old"' >/dev/null
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
fi

# Sentinel plist key survived the update...
if [ "$(/usr/libexec/PlistBuddy -c "Print :SentinelPreserved" "$TMP/to.app/Contents/Info.plist" 2>/dev/null)" != "yes" ]; then
	echo "error: install-update: sentinel plist key not preserved" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
# ...and main.scpt now matches FROM byte-for-byte (transplant)...
if ! cmp -s "$TMP/from.app/Contents/Resources/Scripts/main.scpt" \
	"$TMP/to.app/Contents/Resources/Scripts/main.scpt"; then
	echo "error: install-update: main.scpt was not transplanted from FROM" >&2
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

lib_report "install ok"
