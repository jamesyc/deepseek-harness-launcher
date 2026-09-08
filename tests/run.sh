#!/bin/bash
# Run the full test suite. Usage: ./tests/run.sh
set -uo pipefail
shopt -s nullglob

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

# Lint first so `run.sh` catches what CI's shellcheck step catches.
if command -v shellcheck >/dev/null 2>&1; then
	if shellcheck "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh; then
		echo "PASS shellcheck"
		PASS=$((PASS + 1))
	else
		echo "FAIL shellcheck"
		FAIL=$((FAIL + 1))
	fi
else
	echo "SKIP shellcheck (not installed; CI installs it via brew)"
	SKIP=$((SKIP + 1))
fi

files=("$ROOT"/tests/test_*.sh)
if [ "${#files[@]}" -eq 0 ]; then
	echo "error: no tests found" >&2
	exit 1
fi

for t in "${files[@]}"; do
	name="$(basename "$t")"
	# Isolate env overrides between test files.
	output="$(env -u DEEPSEEK_HARNESS_CONFIG -u DEEPSEEK_HARNESS_LAUNCHER_APP bash "$t" 2>&1)"
	status=$?
	if [ $status -eq 0 ]; then
		if printf '%s' "$output" | grep -q '^SKIP'; then
			echo "SKIP $name"
			printf '%s\n' "$output"
			SKIP=$((SKIP + 1))
		else
			echo "PASS $name"
			printf '%s\n' "$output"
			PASS=$((PASS + 1))
		fi
	else
		echo "FAIL $name"
		printf '%s\n' "$output"
		FAIL=$((FAIL + 1))
	fi
done

echo "---"
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
