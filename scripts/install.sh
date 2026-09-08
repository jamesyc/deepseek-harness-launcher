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
	# Best-effort read of the file-picker cache, which lives in main.scpt
	# and is therefore reset by the transplant below. Never fails the
	# install: old/stub bundles may lack the property entirely.
	old_cache="$(/usr/bin/osascript \
		-e "set s to load script POSIX file \"$TO/Contents/Resources/Scripts/main.scpt\"" \
		-e 'get resolvedChromeAppPath of s' 2>/dev/null || true)"
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

# The transplant resets the file-picker cache, so say so when there was one.
# (Deliberately not restored: a cached /Users/<name>/ path would trip
# verify.sh's no-hardcoded-paths gate. CHROME_APP in the config file is the
# persistent choice — it lives outside the bundle and survives updates.)
if [ -n "${old_cache:-}" ]; then
	echo "note: the file-picker choice was reset by this update; set CHROME_APP in ~/.config/deepseek-harness-launcher/config to persist it"
fi
