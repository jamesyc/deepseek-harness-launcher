#!/bin/bash
# scripts/build.sh argument handling and bundle properties.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

# --help exits 0 and mentions usage.
if ! "$ROOT/scripts/build.sh" --help 2>/dev/null | grep -q 'Usage:'; then
	echo "error: build-help: expected usage text" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi

# Unknown args are rejected.
expect_fail "build-unknown-arg" "$ROOT/scripts/build.sh" --bogus
expect_fail "build-missing-value" "$ROOT/scripts/build.sh" --output

# Both --output forms work and produce a signed bundle with LSUIElement.
"$ROOT/scripts/build.sh" --output "$TMP/space.app" >/dev/null
"$ROOT/scripts/build.sh" --output="$TMP/eq.app" >/dev/null
for app in "$TMP/space.app" "$TMP/eq.app"; do
	test -f "$app/Contents/Resources/Scripts/main.scpt" || {
		echo "error: missing main.scpt in $app" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	}
	if [ "$(plutil -extract LSUIElement raw "$app/Contents/Info.plist")" != "true" ]; then
		echo "error: LSUIElement != true in $app" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
	if ! /usr/bin/codesign --verify --deep "$app" 2>/dev/null; then
		echo "error: codesign verify failed for $app" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
done

# Rebuilding over an existing output succeeds (rm -rf + recompile).
"$ROOT/scripts/build.sh" --output "$TMP/space.app" >/dev/null
test -f "$TMP/space.app/Contents/Resources/Scripts/main.scpt" || {
	echo "error: rebuild-over-existing failed" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
}

lib_report "build args ok"
