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
# Never let `rm -rf "$OUTPUT"` below point at / or $HOME.
case "$OUTPUT" in
	"/"|"$HOME")
		echo "error: refusing to build into $OUTPUT" >&2; exit 1;;
esac

for tool in /usr/bin/osacompile /usr/libexec/PlistBuddy /usr/bin/codesign; do
	if [ ! -x "$tool" ]; then
		echo "error: required tool missing: $tool" >&2; exit 1
	fi
done

mkdir -p "$(dirname "$OUTPUT")"
rm -rf "$OUTPUT"

/usr/bin/osacompile -s -o "$OUTPUT" "$ROOT/src/deepseek-harness-launcher.applescript"

# osacompile-built stay-open applets lack LSUIElement (Dock icon); add it so
# the launcher runs without a Dock icon, then re-sign (editing Info.plist
# invalidates the original signature). Set-or-Add survives template changes
# if a future osacompile ever ships the key itself.
/usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$OUTPUT/Contents/Info.plist" >/dev/null 2>&1 || \
	/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$OUTPUT/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$OUTPUT"

# Fail the build here rather than at install/verify time.
/usr/bin/plutil -lint "$OUTPUT/Contents/Info.plist" >/dev/null
/usr/bin/codesign --verify --deep "$OUTPUT"

echo "built: $OUTPUT"
