#!/bin/bash
# Token URL scrape + chromeless window launch (src handlers) without needing
# dsh or a real window.
# dsh prints `dsh web: <url>` on startup (bare on old servers, token-bearing
# on new ones); the launcher probes it verbatim and opens it in the nested
# window bundle (own Dock icon, no browser involved). The binary takes the
# URL as argv, so $! is the window process and the idle watchdog can track
# it out of the box.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

need_macos "osacompile/osascript missing"
setup_tmp

SCPT="$TMP/appwin.scpt"
/usr/bin/osacompile -o "$SCPT" "$ROOT/src/deepseek-harness-launcher.applescript"

ask() { # ask '<handler call>' -> prints handler result
	/usr/bin/osascript -e "set h to load script POSIX file \"$SCPT\"" -e "tell h to $1"
}

# Parity: if the src scrape breaks, the launcher never finds the server URL;
# if the ephemeral-port flag goes missing, the window URL has no port to use.
if ! grep -F -q 'dsh web: http' "$ROOT/src/deepseek-harness-launcher.applescript"; then
	echo "error: server URL scrape marker in src drifted; update $0" >&2
	exit 1
fi
if ! grep -F -q -- '--port 0' "$ROOT/src/deepseek-harness-launcher.applescript"; then
	echo "error: ephemeral-port flag in src drifted; update $0" >&2
	exit 1
fi

# serverURLFromLog(): token, bare, last-wins, empty, missing.
printf '%s\n' 'starting up' 'dsh web: http://127.0.0.1:54621/?token=AbC_123-xyz' > "$TMP/tok.log"
check "token-url" "http://127.0.0.1:54621/?token=AbC_123-xyz" "$(ask 'serverURLFromLog("'"$TMP"'/tok.log")')"
printf '%s\n' 'dsh web: http://127.0.0.1:3080/' > "$TMP/bare.log"
check "bare-url" "http://127.0.0.1:3080/" "$(ask 'serverURLFromLog("'"$TMP"'/bare.log")')"
printf '%s\n' 'dsh web: http://127.0.0.1:1111/?token=first' 'dsh web: http://127.0.0.1:2222/?token=second' > "$TMP/multi.log"
check "last-wins" "http://127.0.0.1:2222/?token=second" "$(ask 'serverURLFromLog("'"$TMP"'/multi.log")')"
printf '%s\n' 'no startup line here' > "$TMP/empty.log"
check "no-match-empty" "" "$(ask 'serverURLFromLog("'"$TMP"'/empty.log")')"
check "missing-file-empty" "" "$(ask 'serverURLFromLog("'"$TMP"'/does-not-exist.log")')"

# portOfURL(): the listener PID is re-resolved on the scraped port.
check "port-token" "54621" "$(ask 'portOfURL("http://127.0.0.1:54621/?token=x")')"
check "port-bare" "3080" "$(ask 'portOfURL("http://127.0.0.1:3080/")')"
check "port-garbage" "" "$(ask 'portOfURL("garbage")')"
check "port-empty" "" "$(ask 'portOfURL("")')"

# bareStatusCode(): 200 live, 000 closed. (401 is the token fence, pinned
# against live dsh 0.1.5 during development; no dsh binary is needed here.)
P_ORIG="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
(cd "$TMP" && nohup python3 -m http.server "$P_ORIG" --bind 127.0.0.1 >"$TMP/origin.log" 2>&1 < /dev/null & echo $! > "$TMP/origin.pid")
sleep 1
check "status-live" "200" "$(ask "bareStatusCode(\"http://127.0.0.1:$P_ORIG/\")")"
check "status-closed" "000" "$(ask 'bareStatusCode("http://127.0.0.1:9/")')"

# windowCommandFor(): composition carries the binary path and the URL, and
# never routes through open (the window must be its own process).
mkdir -p "$TMP/ws"
TOKEN_URL="http://127.0.0.1:$P_ORIG/?token=WinTest-123"
CMD="$(ask "windowCommandFor(\"/bin/echo\", \"$TOKEN_URL\", \"$TMP/ws\", \"$TMP/win.log\")")"
printf '%s\n' "$CMD" > "$TMP/cmd.txt"
assert_file_contains "$TMP/cmd.txt" '/bin/echo' "window-binary"
assert_file_contains "$TMP/cmd.txt" "$TOKEN_URL" "window-url"
if grep -q 'open' "$TMP/cmd.txt"; then
	echo "error: window-command must exec the binary directly (open would merge or detach)" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi

# windowCommandFor(): launch grammar returns instantly with a trackable
# PID. A fake binary (exec sleep: dies on TERM like the window process)
# stands in for the real thing so no window opens.
printf '%s\n' '#!/bin/sh' 'exec /bin/sleep 30' > "$TMP/fake-window"
chmod +x "$TMP/fake-window"
CMD="$(ask "windowCommandFor(\"$TMP/fake-window\", \"$TOKEN_URL\", \"$TMP/ws\", \"$TMP/win2.log\")")"
if [ -z "$CMD" ]; then
	echo "error: windowCommandFor returned empty" >&2
	exit 1
fi
rm -f "$TMP/win.pid" "$TMP/win.done"
( out=$(/bin/sh -c "$CMD"); printf '%s' "$out" > "$TMP/win.pid"; touch "$TMP/win.done" ) &
waiter=$!
ready=""
i=0
while [ "$i" -lt 8 ] && [ -z "$ready" ]; do
	if [ -f "$TMP/win.done" ]; then ready="yes"; fi
	if [ -z "$ready" ]; then sleep 0.5; i=$((i + 1)); fi
done
if [ -z "$ready" ]; then
	echo "error: window command did not return within 4s (do shell script would hang forever)" >&2
	kill "$waiter" 2>/dev/null || true
	exit 1
fi
wait "$waiter" 2>/dev/null || true
WIN_PID="$(tr -d '[:space:]' < "$TMP/win.pid")"
case "$WIN_PID" in
	''|*[!0-9]*) echo "error: window launch did not print a numeric PID, got [$WIN_PID]" >&2; exit 1;;
esac
if ! /bin/kill -0 "$WIN_PID" 2>/dev/null; then
	echo "error: window PID $WIN_PID is not alive" >&2
	exit 1
fi
/bin/kill -TERM "$WIN_PID" 2>/dev/null || true
i=0
while [ "$i" -lt 6 ] && /bin/kill -0 "$WIN_PID" 2>/dev/null; do
	sleep 0.5
	i=$((i + 1))
done
if /bin/kill -0 "$WIN_PID" 2>/dev/null; then
	echo "error: could not reap test window $WIN_PID" >&2
	exit 1
fi

# stopStaleWindows(): reaps same-binary holders precisely, spares the rest.
# NOTE: the fixture path is split ("fake-" & "window") so the test's own
# osascript command line never contains it contiguously (it would match).
bash -c "exec -a \"$TMP/fake-window\" /bin/sleep 30" &
sleep 1
STALE="$(/usr/bin/pgrep -f -- "$TMP/fake-window" || true)"
if [ -z "$STALE" ]; then
	echo "error: stale-window fixture did not start" >&2
	exit 1
fi
/bin/sleep 30 &
INNOCENT=$!
ask "stopStaleWindows(\"$TMP/fake-\" & \"window\")" >/dev/null
i=0
while [ "$i" -lt 10 ] && /usr/bin/pgrep -f -- "$TMP/fake-window" >/dev/null 2>&1; do
	sleep 0.5
	i=$((i + 1))
done
if /usr/bin/pgrep -f -- "$TMP/fake-window" >/dev/null 2>&1; then
	echo "error: stale window holder survived the sweep" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
if ! /bin/kill -0 "$INNOCENT" 2>/dev/null; then
	echo "error: sweep killed an unrelated process" >&2
	LIB_FAILS=$((LIB_FAILS + 1))
fi
/bin/kill -TERM "$INNOCENT" 2>/dev/null || true
/bin/kill -TERM "$(cat "$TMP/origin.pid")" 2>/dev/null || true

lib_report "app window ok"
