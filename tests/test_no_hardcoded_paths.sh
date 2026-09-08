#!/bin/bash
# Neither the source nor the compiled output may contain /Users/ paths
# (publishing a hardcoded username leaks PII and breaks portability).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if grep -n '/Users/' "$ROOT/src/deepseek-harness-launcher.applescript"; then
	echo "error: hardcoded /Users/ path in src" >&2
	exit 1
fi

/usr/bin/osacompile -s -o "$TMP/check.app" "$ROOT/src/deepseek-harness-launcher.applescript"
if /usr/bin/osadecompile "$TMP/check.app" | grep -q '/Users/'; then
	echo "error: hardcoded /Users/ path in compiled output" >&2
	exit 1
fi

echo "no hardcoded paths"
