#!/bin/bash
# Install DeepSeek Harness Launcher.app into ~/Applications.
# Full-copy install: stages and verifies a fresh build, backs up any existing
# bundle to $TMPDIR, then replaces it with rollback on failure. Bundle identity
# and icon ship from source (assets/bundle-identity, assets/applet.icns), so a
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

mkdir -p "$(dirname "$TO")"
stage_dir="$(mktemp -d "$(dirname "$TO")/.deepseek-install.XXXXXXXX")"
# Preserve the old app in stage_dir if a rollback itself fails.
trap 'if [ -e "$stage_dir/previous.app" ] || [ -L "$stage_dir/previous.app" ]; then echo "recovery copy kept at: $stage_dir/previous.app" >&2; else rm -rf "$stage_dir"; fi' EXIT
staged_app="$stage_dir/new.app"
/usr/bin/ditto "$FROM" "$staged_app"
/usr/bin/codesign --force --deep --sign - "$staged_app"
"$ROOT/scripts/verify.sh" "$staged_app"

had_existing=0
if [ -e "$TO" ] || [ -L "$TO" ]; then
	if [ ! -d "$TO" ]; then
		echo "error: install target exists but is not an app directory: $TO" >&2
		exit 1
	fi
	backup_dir="${TMPDIR:-/tmp}"
	mkdir -p "$backup_dir"
	backup="$backup_dir/DeepSeek-Harness-Launcher-backup-$(date +%Y%m%d-%H%M%S)-$$.app"
	/usr/bin/ditto "$TO" "$backup"
	echo "backed up existing app to: $backup"
	/bin/mv "$TO" "$stage_dir/previous.app"
	had_existing=1
fi

if ! /bin/mv "$staged_app" "$TO"; then
	if [ "$had_existing" -eq 1 ]; then /bin/mv "$stage_dir/previous.app" "$TO"; fi
	echo "error: could not replace app at $TO" >&2
	exit 1
fi
if ! "$ROOT/scripts/verify.sh" "$TO"; then
	/bin/mv "$TO" "$stage_dir/failed.app" || true
	if [ "$had_existing" -eq 1 ]; then /bin/mv "$stage_dir/previous.app" "$TO"; fi
	echo "error: installed app failed verification" >&2
	exit 1
fi

if [ "$had_existing" -eq 1 ]; then
	rm -rf "$stage_dir/previous.app"
	echo "updated existing app at: $TO"
	# Keep only the 5 newest backups after a successful replacement.
	# shellcheck disable=SC2012
	ls -dt "$backup_dir"/DeepSeek-Harness-Launcher-backup-*.app 2>/dev/null | tail -n +6 | while IFS= read -r old; do
		rm -rf "$old" || true
	done || true
else
	echo "fresh install to: $TO"
fi
