#!/bin/bash
# Guardrail: no producer-into-grep pipes under `set -o pipefail`.
# Rationale is documented in tests/lib.sh (assert_file_contains): grep -q
# exits on first match, the producer then dies on SIGPIPE, and pipefail
# reports failure even when the pattern matched. Capture to a file first.
# Runs anywhere (pure shell, no osacompile).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

# NOTE: no setup_tmp/need_macos — pure grep, runs on Linux too.
hits="$(grep -rn --include='*.sh' -E '\| (/usr/bin/)?grep' "$ROOT/scripts" "$ROOT/tests" || true)"
# Exclusions (filename-prefixed, so they also cover self-matches in this file):
# - this guardrail: its own implementation pipes into grep -v (file-backed
#   grep of already-captured text, safe by construction).
# - test_port_match.sh: printf of tiny literals into grep -E (infallible
#   producer, fully consumed input, safe by construction).
hits="$(printf '%s\n' "$hits" | grep -v -e 'test_no_pipe_grep.sh' -e 'test_port_match.sh' || true)"
if [ -n "$hits" ]; then
	echo "error: producer-into-grep pipes found (capture to a file first):" >&2
	printf '%s\n' "$hits" >&2
	exit 1
fi

echo "no pipe-grep"
