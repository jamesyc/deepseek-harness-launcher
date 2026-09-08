#!/bin/bash
# The AppleScript source must compile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

need_macos "osacompile missing"
setup_tmp

/usr/bin/osacompile -s -o "$TMP/check.app" "$ROOT/src/deepseek-harness-launcher.applescript"
test -f "$TMP/check.app/Contents/Resources/Scripts/main.scpt"
echo "compile ok"
