#!/bin/bash
# Build DeepSeek Harness Launcher.app from src/.
# Usage: ./scripts/build.sh [--output PATH]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT=""

while [ $# -gt 0 ]; do
	case "$1" in
		--output)
			OUTPUT="${2:?missing value for --output}"; shift 2;;
		--output=*)
			OUTPUT="${1#--output=}"; shift;;
		-h|--help)
			echo "Usage: ./scripts/build.sh [--output PATH]"; exit 0;;
		*)
			echo "error: unknown arg: $1" >&2; exit 1;;
	esac
done

OUTPUT="${OUTPUT:-$ROOT/build/DeepSeek Harness Launcher.app}"
: "${OUTPUT:?}"
mkdir -p "$(dirname "$OUTPUT")"
rm -rf "$OUTPUT"

/usr/bin/osacompile -s -o "$OUTPUT" "$ROOT/src/deepseek-harness-launcher.applescript"

# osacompile-built stay-open applets lack LSUIElement (Dock icon); add it so
# the launcher runs without a Dock icon, then re-sign (editing Info.plist
# invalidates the original signature).
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$OUTPUT/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$OUTPUT"

echo "built: $OUTPUT"
