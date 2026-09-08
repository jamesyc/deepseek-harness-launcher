#!/bin/bash
# Neither the source nor the compiled output may contain /Users/ paths
# (publishing a hardcoded username leaks PII and breaks portability).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

if grep -n '/Users/' "$ROOT/src/deepseek-harness-launcher.applescript"; then
	echo "error: hardcoded /Users/ path in src" >&2
	exit 1
fi

need_macos "osacompile missing"
setup_tmp

/usr/bin/osacompile -s -o "$TMP/check.app" "$ROOT/src/deepseek-harness-launcher.applescript"
if /usr/bin/osadecompile "$TMP/check.app" | grep -q '/Users/'; then
	echo "error: hardcoded /Users/ path in compiled output" >&2
	/usr/bin/osadecompile "$TMP/check.app" | grep -n '/Users/' >&2 || true
	exit 1
fi

echo "no hardcoded paths"
