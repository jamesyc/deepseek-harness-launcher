#!/bin/bash
# Install DeepSeek Harness Launcher.app into ~/Applications.
# Preserves the existing bundle's ID/icon/plist by transplanting only the
# freshly built main.scpt, then re-signs and verifies.
# Usage: ./scripts/install.sh [--from PATH] [--to PATH]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FROM="$ROOT/build/DeepSeek Harness Launcher.app"
TO="$HOME/Applications/DeepSeek Harness Launcher.app"

while [ $# -gt 0 ]; do
	case "$1" in
		--from)
			FROM="${2:?missing value for --from}"; shift 2;;
		--from=*)
			FROM="${1#--from=}"; shift;;
		--to)
			TO="${2:?missing value for --to}"; shift 2;;
		--to=*)
			TO="${1#--to=}"; shift;;
		-h|--help)
			echo "Usage: ./scripts/install.sh [--from PATH] [--to PATH]"; exit 0;;
		*)
			echo "error: unknown arg: $1" >&2; exit 1;;
	esac
done

if [ ! -d "$FROM" ]; then
	echo "error: build not found at $FROM (run ./scripts/build.sh first)" >&2
	exit 1
fi

if [ -d "$TO" ]; then
	BACKUP="${TMPDIR:-/tmp}/DeepSeek-Harness-Launcher-backup-$(date +%Y%m%d-%H%M%S).app"
	cp -R "$TO" "$BACKUP"
	echo "backed up existing app to: $BACKUP"
	cp "$FROM/Contents/Resources/Scripts/main.scpt" "$TO/Contents/Resources/Scripts/main.scpt"
else
	mkdir -p "$(dirname "$TO")"
	cp -R "$FROM" "$TO"
	echo "fresh install to: $TO"
fi

/usr/bin/codesign --force --deep --sign - "$TO"
"$ROOT/scripts/verify.sh" "$TO"
