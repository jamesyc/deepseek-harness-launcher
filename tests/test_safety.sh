#!/bin/bash
# Safety rails: build output guard, install self-install guard, verify
# signature rejection, and quit TERM->KILL escalation (simulated in shell).
# Pure-shell parts run anywhere; bundle parts skip without macOS tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

setup_tmp

expect_fail() { # expect_fail <label> <command...>
	if "$@" >/dev/null 2>&1; then
		echo "error: $1: expected failure, got success" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}

# build.sh refuses dangerous outputs (pure shell arg parsing; needs
# osacompile only for the happy path, so refusal cases run on Linux too).
expect_fail "build-refuses-root" "$ROOT/scripts/build.sh" --output /
expect_fail "build-refuses-home" "$ROOT/scripts/build.sh" --output "$HOME"
expect_fail "build-refuses-tmpdir" "$ROOT/scripts/build.sh" --output /tmp
expect_fail "build-refuses-no-suffix" "$ROOT/scripts/build.sh" --output "$TMP/notanapp"
expect_fail "build-refuses-home-slash" "$ROOT/scripts/build.sh" --output "$HOME/"

# install.sh self-install guard via stub bundles (no compile needed: the
# stubs satisfy the FROM completeness checks so the self-guard is what
# fires). Assert the message, not just failure, so a completeness error
# can't masquerade as the guard.
mkdir -p "$TMP/self.app/Contents/Resources/Scripts"
touch "$TMP/self.app/Contents/Resources/Scripts/main.scpt"
touch "$TMP/self.app/Contents/Resources/applet.icns"
ln -sfn "$TMP/self.app" "$TMP/self-link.app"
refuse_self() { # refuse_self <label> <to>
	if "$ROOT/scripts/install.sh" --from "$TMP/self.app" --to "$2" >"$TMP/self-$1.txt" 2>&1; then
		echo "error: $1: expected failure, got success" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	elif ! grep -q 'refusing to install onto itself' "$TMP/self-$1.txt"; then
		echo "error: $1: wrong error message:" >&2
		cat "$TMP/self-$1.txt" >&2 || true
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}
# The self-guard sits behind install.sh's required-tools check (ditto,
# codesign: macOS-only), so skip just this block elsewhere. The quit
# simulations below are the portable core of this file and always run.
if [ ! -x /usr/bin/ditto ] || [ ! -x /usr/bin/codesign ]; then
	echo "note: SKIP install-refuses-self (macOS tools missing), other checks below ran"
else
	refuse_self "install-refuses-symlink-self" "$TMP/self-link.app"
	refuse_self "install-refuses-trailing-slash-self" "$TMP/self.app/"
fi

# quit escalation, simulated: cooperative sleeper dies on TERM;
# TERM-ignoring sleeper survives TERM and needs KILL (mirrors on quit).
/bin/sleep 30 &
coop=$!
/bin/kill -TERM "$coop" 2>/dev/null || true
i=0
while [ "$i" -lt 10 ] && /bin/kill -0 "$coop" 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
if /bin/kill -0 "$coop" 2>/dev/null; then
	echo "error: quit-sim-coop: sleeper survived TERM" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
	/bin/kill -KILL "$coop" 2>/dev/null || true
fi
wait "$coop" 2>/dev/null || true

bash -c 'trap "" TERM; exec /bin/sleep 30' &
stubborn=$!
sleep 0.3
/bin/kill -TERM "$stubborn" 2>/dev/null || true
sleep 0.3
if ! /bin/kill -0 "$stubborn" 2>/dev/null; then
	echo "error: quit-sim-stubborn: TERM-ignorer died on TERM (simulation invalid)" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
else
	/bin/kill -KILL "$stubborn" 2>/dev/null || true
	i=0
	while [ "$i" -lt 10 ] && /bin/kill -0 "$stubborn" 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
	if /bin/kill -0 "$stubborn" 2>/dev/null; then
		echo "error: quit-sim-stubborn: sleeper survived KILL" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
fi
wait "$stubborn" 2>/dev/null || true

# verify.sh rejects a tampered signature (macOS only).
if [ ! -x /usr/bin/osacompile ] || [ ! -x /usr/bin/codesign ]; then
	echo "note: SKIP verify-tamper (macOS toolchain missing), other checks above ran"
else
	"$ROOT/scripts/build.sh" --output "$TMP/v.app" >/dev/null
	echo "-- tampered --" >> "$TMP/v.app/Contents/Resources/Scripts/main.scpt"
	expect_fail "verify-rejects-tamper" "$ROOT/scripts/verify.sh" "$TMP/v.app"
fi

lib_report "safety ok"
