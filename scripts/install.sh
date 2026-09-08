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

for tool in /usr/bin/ditto /usr/libexec/PlistBuddy /usr/bin/codesign; do
	if [ ! -x "$tool" ]; then
		echo "error: required tool missing: $tool" >&2; exit 1
	fi
done

if [ ! -d "$FROM" ]; then
	echo "error: build not found at $FROM (run ./scripts/build.sh first)" >&2
	exit 1
fi
if [ ! -f "$FROM/Contents/Resources/Scripts/main.scpt" ]; then
	echo "error: build at $FROM is incomplete (missing main.scpt; re-run ./scripts/build.sh)" >&2
	exit 1
fi
if [ "$FROM" = "$TO" ]; then
	echo "error: --from and --to are the same bundle ($FROM); refusing to install onto itself" >&2
	exit 1
fi

if [ -d "$TO" ]; then
	BACKUP="${TMPDIR:-/tmp}/DeepSeek-Harness-Launcher-backup-$(date +%Y%m%d-%H%M%S).app"
	cp -R "$TO" "$BACKUP"
	echo "backed up existing app to: $BACKUP"
	# The Chrome-app picker cache lives outside the bundle
	# (~/Library/Application Support/...), so the transplant below preserves it.
	cp "$FROM/Contents/Resources/Scripts/main.scpt" "$TO/Contents/Resources/Scripts/main.scpt"
	# The transplant keeps the old Info.plist (bundle ID/icon), but an
	# install from before LSUIElement existed would keep its Dock icon too.
	/usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$TO/Contents/Info.plist" >/dev/null 2>&1 || \
		/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$TO/Contents/Info.plist"
else
	mkdir -p "$(dirname "$TO")"
	cp -R "$FROM" "$TO"
	echo "fresh install to: $TO"
fi

/usr/bin/codesign --force --deep --sign - "$TO"
"$ROOT/scripts/verify.sh" "$TO"
