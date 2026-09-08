#!/bin/bash
# Run the full test suite. Usage: ./tests/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

for t in "$ROOT"/tests/test_*.sh; do
	name="$(basename "$t")"
	if bash "$t"; then
		echo "PASS $name"
		PASS=$((PASS + 1))
	else
		echo "FAIL $name"
		FAIL=$((FAIL + 1))
	fi
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
