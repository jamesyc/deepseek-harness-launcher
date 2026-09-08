#!/bin/bash
# Regression (Sep 2026): the server launch line must return instantly under
# `do shell script` semantics (stdout is a pipe, read until EOF). If `&`
# binds to a compound (&&) list instead of the simple `nohup` command, bash
# forks a subshell that holds the pipe open until the server exits, so `run`
# stalls forever: no Chrome window, no idle watchdog, orphaned server.
# This test executes the REAL string built by launchCommandFor() and fails
# if capturing its stdout does not finish within a few seconds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

need_macos "osacompile/osascript missing"
setup_tmp

SCPT="$TMP/launch.scpt"
/usr/bin/osacompile -o "$SCPT" "$ROOT/src/deepseek-harness-launcher.applescript"

mkdir -p "$TMP/ws"
CMD="$(/usr/bin/osascript \
	-e "set h to load script POSIX file \"$SCPT\"" \
	-e "tell h to launchCommandFor(\"$TMP/ws\", \"sleep 25\", \"$TMP/srv.log\")")"
if [ -z "$CMD" ]; then
	echo "error: launchCommandFor returned empty" >&2
	exit 1
fi

# Simulate `do shell script`: stdout is a pipe consumed until EOF.
rm -f "$TMP/pid.txt" "$TMP/done"
( out=$(/bin/sh -c "$CMD"); printf '%s' "$out" > "$TMP/pid.txt"; touch "$TMP/done" ) &
waiter=$!

ready=""
i=0
while [ "$i" -lt 8 ] && [ -z "$ready" ]; do
	if [ -f "$TMP/done" ]; then ready="yes"; fi
	if [ -z "$ready" ]; then sleep 0.5; i=$((i + 1)); fi
done

if [ -z "$ready" ]; then
	echo "error: launch command did not return within 4s (do shell script would hang forever)" >&2
	kill "$waiter" 2>/dev/null || true
	# Exact full-command match: only the test sleeper looks like this.
	/usr/bin/pkill -f '^sleep 25$' 2>/dev/null || true
	exit 1
fi

PID="$(tr -d '[:space:]' < "$TMP/pid.txt")"
case "$PID" in
	''|*[!0-9]*) echo "error: launch did not print a numeric PID, got [$PID]" >&2; exit 1;;
esac
if ! /bin/kill -0 "$PID" 2>/dev/null; then
	echo "error: launched PID $PID is not alive (server did not start)" >&2
	exit 1
fi
if [ ! -f "$TMP/srv.log" ]; then
	echo "error: server log was not created" >&2
	/bin/kill -KILL "$PID" 2>/dev/null || true
	exit 1
fi

/bin/kill -KILL "$PID" 2>/dev/null || true
i=0
while [ "$i" -lt 6 ] && /bin/kill -0 "$PID" 2>/dev/null; do
	sleep 0.5
	i=$((i + 1))
done
if /bin/kill -0 "$PID" 2>/dev/null; then
	echo "error: could not reap test sleeper $PID" >&2
	exit 1
fi
wait "$waiter" 2>/dev/null || true

echo "launch returns ok"
