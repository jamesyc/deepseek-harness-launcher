#!/bin/bash
# The AppleScript source must compile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

/usr/bin/osacompile -s -o "$TMP/check.app" "$ROOT/src/deepseek-harness-launcher.applescript"
test -f "$TMP/check.app/Contents/Resources/Scripts/main.scpt"
echo "compile ok"
