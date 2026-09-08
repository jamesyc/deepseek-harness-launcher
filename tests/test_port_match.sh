#!/bin/bash
# The port-owner check (src: `ps ... | grep -E -q '<regex>'`) decides whether
# the launcher adopts the listener or aborts with "already in use".
# A loose regex would adopt (and later kill) the wrong program; a strict one
# would refuse to adopt the real dsh server. Pin both directions here.
# Runs anywhere (pure shell, no osacompile).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
. "$ROOT/tests/lib.sh"

setup_tmp

# Keep parity with src/deepseek-harness-launcher.applescript (ps/grep line):
# if the source regex changes, this grep fails and forces a test update.
REG='(^|[ /])dsh( |$| web)|@deepseek-ai/dsh'
if ! grep -F -q "$REG" "$ROOT/src/deepseek-harness-launcher.applescript"; then
	echo "error: port regex in src drifted; update REG in $0" >&2
	exit 1
fi

should_match() { # should_match <label> <ps line>
	if printf '%s' "$2" | grep -E -q "$REG"; then
		:
	else
		echo "error: $1: expected MATCH, got reject [$2]" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}
should_reject() { # should_reject <label> <ps line>
	if printf '%s' "$2" | grep -E -q "$REG"; then
		echo "error: $1: expected reject, got MATCH [$2]" >&2
		LIB_FAILS=$((LIB_FAILS + 1))
	fi
}

# Real server command lines (must adopt).
should_match "mise-arm" "/opt/homebrew/bin/mise exec -- dsh web --no-open"
should_match "mise-intel" "/usr/local/bin/mise exec -- dsh web --no-open"
should_match "mise-path" "mise exec -- dsh web --no-open"
should_match "npx" "npx -y @deepseek-ai/dsh web --no-open"
should_match "dsh-binary" "/opt/homebrew/bin/dsh web --no-open"
should_match "dsh-bare" "dsh web --no-open"

# Lookalikes (must NOT adopt — word boundaries matter).
should_reject "hyphen-tool" "my-dsh-tool --port 3080"
should_reject "notes-file" "vim dsh-notes.txt"
should_reject "python-script" "/usr/bin/python dsh_server.py"
should_reject "prefix-chars" "edsh web --no-open"
should_reject "chrome-loader" "app_mode_loader --app=http://127.0.0.1:3080"
should_reject "node-other" "node server.js"

lib_report "port match ok"
