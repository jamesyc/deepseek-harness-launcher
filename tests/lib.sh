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

# File-backed grep assertions. Never pipe a producer into grep -q under `set -o
# pipefail`: grep -q exits on first match, the producer then dies on SIGPIPE,
# and pipefail reports failure even when the pattern matched (likewise,
# negated pipe checks misfire when the producer exits non-zero).
# Capture output to a file first, then grep the file.
# Usage: assert_file_contains <file> <pattern> <label>
assert_file_contains() {
	if ! grep -q "$2" "$1"; then
		echo "error: $3: pattern [$2] not found in $1" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}

# Usage: assert_file_absent <file> <pattern> <label>
assert_file_absent() {
	if grep -q "$2" "$1"; then
		echo "error: $3: unexpected pattern [$2] in $1" >&2
		grep -n "$2" "$1" >&2 || true
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}
