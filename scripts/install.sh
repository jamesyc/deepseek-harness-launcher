#!/bin/bash
# Install DeepSeek Harness Launcher.app into ~/Applications.
# Full-copy install: backs up any existing bundle to $TMPDIR, replaces it
# with the fresh build, then re-signs and verifies. Bundle identity and the
# icon ship from source (assets/bundle-identity, assets/applet.icns), so a
# full copy is always correct — nothing in the old bundle is worth keeping.
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

for tool in /usr/bin/ditto /usr/bin/codesign; do
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
if [ ! -f "$FROM/Contents/Resources/applet.icns" ]; then
	echo "error: build at $FROM is incomplete (missing applet.icns; re-run ./scripts/build.sh)" >&2
	exit 1
fi
# Canonicalize so symlinks, relative paths, and trailing slashes can't
# disguise installing a bundle onto itself.
canon() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || printf '%s' "$1"; }
if [ "$(canon "${FROM%/}")" = "$(canon "${TO%/}")" ]; then
	echo "error: --from and --to are the same bundle ($FROM); refusing to install onto itself" >&2
	exit 1
fi
# The install below does `rm -rf "$TO"`, so refuse system locations and
# non-.app targets the same way build.sh refuses dangerous outputs.
canon_to="$(canon "${TO%/}")"
case "$canon_to" in
	*.app) ;;
	*)
		echo "error: refusing to install into $TO (must end in .app)" >&2; exit 1;;
esac
case "$canon_to" in
	"/"|"$HOME"|"/Applications"|"/System"|"/System/"*)
		echo "error: refusing to install into $TO" >&2; exit 1;;
esac

had_existing=0
if [ -d "$TO" ]; then
	BACKUP="${TMPDIR:-/tmp}/DeepSeek-Harness-Launcher-backup-$(date +%Y%m%d-%H%M%S).app"
	/usr/bin/ditto "$TO" "$BACKUP"
	echo "backed up existing app to: $BACKUP"
	# Keep only the 5 newest backups; best-effort, never fails the install.
	BACKUP_DIR="${TMPDIR:-/tmp}"
	# shellcheck disable=SC2012
	ls -dt "$BACKUP_DIR"/DeepSeek-Harness-Launcher-backup-*.app 2>/dev/null | tail -n +6 | while IFS= read -r old; do
		rm -rf "$old" || true
	done || true
	had_existing=1
	rm -rf "$TO"
fi

mkdir -p "$(dirname "$TO")"
/usr/bin/ditto "$FROM" "$TO"
if [ "$had_existing" -eq 1 ]; then
	echo "updated existing app at: $TO"
else
	echo "fresh install to: $TO"
fi

/usr/bin/codesign --force --deep --sign - "$TO"
"$ROOT/scripts/verify.sh" "$TO"
