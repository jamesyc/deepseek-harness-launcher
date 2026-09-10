#!/bin/bash
# End-to-end: build a bundle and run scripts/verify.sh against it,
# plus negative cases proving verify.sh actually rejects bad bundles.
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

# Happy path: positional arg and env-var forms both verify.
"$ROOT/scripts/build.sh" --output "$TMP/v.app" >/dev/null
"$ROOT/scripts/verify.sh" "$TMP/v.app" >/dev/null
DEEPSEEK_HARNESS_LAUNCHER_APP="$TMP/v.app" "$ROOT/scripts/verify.sh" >/dev/null

# Missing bundle fails.
expect_fail "verify-missing-bundle" "$ROOT/scripts/verify.sh" "$TMP/nope.app"

# Bundle without the server strings fails (stub main.scpt).
cp -R "$TMP/v.app" "$TMP/nostrings.app"
/usr/bin/osacompile -o "$TMP/nostrings.app/Contents/Resources/Scripts/main.scpt" \
	-e 'display dialog "hi"' >/dev/null
expect_fail "verify-missing-strings" "$ROOT/scripts/verify.sh" "$TMP/nostrings.app"

# Bundle without LSUIElement fails.
cp -R "$TMP/v.app" "$TMP/nolsui.app"
/usr/libexec/PlistBuddy -c "Delete :LSUIElement" "$TMP/nolsui.app/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$TMP/nolsui.app" >/dev/null 2>&1
expect_fail "verify-missing-lsuielement" "$ROOT/scripts/verify.sh" "$TMP/nolsui.app"

# Bundle without applet.icns fails.
cp -R "$TMP/v.app" "$TMP/noicon.app"
rm "$TMP/noicon.app/Contents/Resources/applet.icns"
expect_fail "verify-missing-icon" "$ROOT/scripts/verify.sh" "$TMP/noicon.app"

# Bundle with a foreign icon fails at the icon gate specifically
# (re-signed so the signature check can't mask it).
cp -R "$TMP/v.app" "$TMP/badicon.app"
printf 'not-an-icon' > "$TMP/badicon.app/Contents/Resources/applet.icns"
/usr/bin/codesign --force --deep --sign - "$TMP/badicon.app" >/dev/null 2>&1
if "$ROOT/scripts/verify.sh" "$TMP/badicon.app" >"$TMP/badicon-out.txt" 2>&1; then
	echo "error: verify-foreign-icon: expected failure, got success" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
elif ! grep -q 'does not match assets/applet.icns' "$TMP/badicon-out.txt"; then
	echo "error: verify-foreign-icon: wrong error message:" >&2
	cat "$TMP/badicon-out.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
fi

# Bundle with a CFBundleIdentifier fails at the identity gate (re-signed so
# the signature check can't mask it).
cp -R "$TMP/v.app" "$TMP/withid.app"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.example.test" \
	"$TMP/withid.app/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$TMP/withid.app" >/dev/null 2>&1
if "$ROOT/scripts/verify.sh" "$TMP/withid.app" >"$TMP/withid-out.txt" 2>&1; then
	echo "error: verify-identifier-absent: expected failure, got success" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
elif ! grep -q 'CFBundleIdentifier must be absent' "$TMP/withid-out.txt"; then
	echo "error: verify-identifier-absent: wrong error message:" >&2
	cat "$TMP/withid-out.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
fi

# Bundle with the wrong display name fails at the identity gate.
cp -R "$TMP/v.app" "$TMP/badname.app"
/usr/libexec/PlistBuddy -c "Delete :CFBundleDisplayName" \
	"$TMP/badname.app/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Wrong Name" \
	"$TMP/badname.app/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$TMP/badname.app" >/dev/null 2>&1
if "$ROOT/scripts/verify.sh" "$TMP/badname.app" >"$TMP/badname-out.txt" 2>&1; then
	echo "error: verify-display-name: expected failure, got success" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
elif ! grep -q 'CFBundleDisplayName' "$TMP/badname-out.txt"; then
	echo "error: verify-display-name: wrong error message:" >&2
	cat "$TMP/badname-out.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
fi

# Bundle with CFBundleIconName present fails at the identity gate.
cp -R "$TMP/v.app" "$TMP/withiconname.app"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string applet" \
	"$TMP/withiconname.app/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - "$TMP/withiconname.app" >/dev/null 2>&1
if "$ROOT/scripts/verify.sh" "$TMP/withiconname.app" >"$TMP/withiconname-out.txt" 2>&1; then
	echo "error: verify-iconname-absent: expected failure, got success" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
elif ! grep -q 'CFBundleIconName must be absent' "$TMP/withiconname-out.txt"; then
	echo "error: verify-iconname-absent: wrong error message:" >&2
	cat "$TMP/withiconname-out.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
fi

# Bundle that is otherwise valid but contains a /Users/ path fails
# at the hardcoded-path gate specifically (not an earlier string check).
cp -R "$TMP/v.app" "$TMP/poisoned.app"
{
	echo 'property evil : "/Users/poison"'
	cat "$ROOT/src/deepseek-harness-launcher.applescript"
} > "$TMP/poison.applescript"
/usr/bin/osacompile -o "$TMP/poisoned.app/Contents/Resources/Scripts/main.scpt" \
	"$TMP/poison.applescript"
# NOTE: capture to a file instead of piping into grep — pipefail would report
# verify's exit 1 even when grep matches.
if "$ROOT/scripts/verify.sh" "$TMP/poisoned.app" >"$TMP/poison-out.txt" 2>&1; then
	echo "error: verify-hardcoded-users: expected failure, got success" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
elif ! grep -q 'hardcoded /Users/' "$TMP/poison-out.txt"; then
	echo "error: verify-hardcoded-users: wrong error message:" >&2
	cat "$TMP/poison-out.txt" >&2 || true
	LIB_FAILS=$((LIB_FAILS + 1))
fi

lib_report "verify ok"
