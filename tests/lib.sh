#!/bin/bash
# Shared test helpers. Source from tests/test_*.sh:
#   ROOT="$(cd "$(dirname "$0")/.." && pwd)"
#   # shellcheck source=lib.sh
#   . "$ROOT/tests/lib.sh"
# shellcheck disable=SC2034
LIB_SH_LOADED=1

# Skip gracefully when the AppleScript toolchain is missing (e.g. Linux).
# Usage: need_macos "reason"
need_macos() {
	if [ ! -x /usr/bin/osacompile ] || [ ! -x /usr/bin/osascript ]; then
		echo "SKIP ${1:-macOS AppleScript toolchain (osacompile/osascript) not found}"
		exit 0
	fi
}

# Create a temp dir tracked for cleanup. Usage: setup_tmp  (sets $TMP)
setup_tmp() {
	TMP="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf \"$TMP\"" EXIT
}

# Accumulating assertion helper (does not exit on first failure).
# Usage: check <label> <expected> <actual>
# Increments LIB_FAILS; call lib_report at the end.
LIB_FAILS=0
check() {
	if [ "${2:-}" != "${3:-}" ]; then
		echo "error: $1: expected [$2], got [$3]" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}

# Report accumulated check() failures. Usage: lib_report "<success message>"
lib_report() {
	if [ "$LIB_FAILS" -ne 0 ]; then
		echo "error: $LIB_FAILS check(s) failed" >&2
		return 1
	fi
	echo "$1"
}
