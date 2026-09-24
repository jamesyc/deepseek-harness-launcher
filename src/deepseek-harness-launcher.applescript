property serverPID : ""
property chromePID : ""
property ownsServer : false

property serverPort : 3080
property configRelPath : ".config/deepseek-harness-launcher/config"

on run
	set serverPID to ""
	set chromePID to ""
	set ownsServer to false
	set targetURL to ""

	-- Single-instance guard: a second launch just focuses the running one.
	-- Pure shell (no System Events), so no extra Automation permission prompt.
	set myBundle to POSIX path of (path to me)
	if myBundle ends with "/" then set myBundle to text 1 thru -2 of myBundle
	set instanceCount to (do shell script "/bin/ps -axww -o command= | /usr/bin/grep -F " & quoted form of myBundle & " | /usr/bin/grep -v grep | /usr/bin/wc -l | /usr/bin/tr -d ' '") as integer
	if instanceCount > 1 then
		do shell script "/usr/bin/open " & quoted form of myBundle
		quit
		return
	end if

	set activePort to effectiveServerPort()
	set portText to (activePort as text)
	set wsPath to effectiveWorkspacePath()
	set logFile to effectiveLogFilePath()
	set checkURLs to serverCheckURLs(portText)

	set existingPIDs to do shell script "/usr/sbin/lsof -nP -tiTCP:" & portText & " -sTCP:LISTEN 2>/dev/null || true"
	if existingPIDs is not "" then
		set adoptedPID to dshPidAmongListeners(existingPIDs)
		if adoptedPID is "" then
			display dialog "Port " & portText & " is already in use by another program." buttons {"OK"} default button "OK" with icon stop
			quit
			return
		end if
		-- Adopt the running server: track it so idle notices if it dies,
		-- but ownsServer stays false so quit never kills what it didn't start.
		set serverPID to adoptedPID
		-- Pick the window URL: a bare 200 is an old server, a 401 is the
		-- token fence (rejected below -- the token is unknowable for a
		-- server we didn't start), anything else keeps legacy leniency.
		set code4 to bareStatusCode(item 1 of checkURLs)
		if code4 is "200" then
			set targetURL to item 1 of checkURLs
		else if code4 is "401" then
			set targetURL to ""
		else
			set code6 to bareStatusCode(item 2 of checkURLs)
			if code6 is "200" then
				set targetURL to item 2 of checkURLs
			else if code6 is "401" then
				set targetURL to ""
			else
				set targetURL to item 1 of checkURLs
			end if
		end if
		if targetURL is "" then
			display dialog "The running DeepSeek Harness server requires authentication. Stop it and relaunch, letting the launcher start the server — or open the token URL printed by 'dsh web' yourself." buttons {"OK"} default button "OK" with icon stop
			quit
			return
		end if
	else
		do shell script "/bin/mkdir -p " & quoted form of wsPath
		-- Fresh log per run so a failure dialog shows this attempt, not history.
		-- Rotate a large previous log to .1 first (single backup, 5 MB threshold).
		set logDir to do shell script "/usr/bin/dirname " & quoted form of logFile
		do shell script "/bin/mkdir -p " & quoted form of logDir
		rotateLogIfNeeded(logFile)
		do shell script ": > " & quoted form of logFile & " || true"
		set dshCommand to effectiveDshCommand()
		-- The window opens the scraped server URL directly, so let the OS
		-- pick the server port; an override that already sets --port is
		-- left alone.
		if dshCommand does not contain "--port" then
			set dshCommand to dshCommand & " --port 0"
		end if
		set launchCommand to launchCommandFor(wsPath, dshCommand, logFile)
		-- Must return instantly; a hang here stalls run forever (no Chrome,
		-- no idle, no quit handling). Guaranteed by launchCommandFor's shell
		-- grammar -- see its comment. (Note: `with timeout` does NOT bound
		-- `do shell script`, so it cannot guard this call.)
		set serverPID to do shell script launchCommand
		set ownsServer to true

		-- Wait for the `dsh web: <url>` startup line, then probe that URL.
		-- Old servers print a bare URL, new ones a token URL; probing the
		-- printed URL verbatim serves both, so no version check is needed.
		set serverReady to false
		repeat 90 times
			set targetURL to serverURLFromLog(logFile)
			if targetURL starts with "http" then
				try
					-- --noproxy: loopback must never go through a proxy
					-- (a proxy env would break every probe for proxied users).
					do shell script "/usr/bin/curl --fail --silent --max-time 1 --noproxy '*' " & quoted form of targetURL & " >/dev/null"
					set serverReady to true
					exit repeat
				end try
			end if
			delay 0.5
		end repeat

		if serverReady is false then
			set logTail to ""
			try
				set logTail to do shell script "/usr/bin/tail -n 20 " & quoted form of logFile & " 2>/dev/null || true"
			end try
			if logTail is not "" then
				set userChoice to button returned of (display dialog "DeepSeek Harness did not start." & return & return & "Last log lines:" & return & logTail buttons {"Show Log", "OK"} default button "OK" with icon stop)
				if userChoice is "Show Log" then
					do shell script "/usr/bin/open " & quoted form of logFile
				end if
			else
				display dialog "DeepSeek Harness did not start. See " & logFile buttons {"OK"} default button "OK" with icon stop
			end if
			quit
			return
		end if

		-- Re-resolve the listener PID, but keep the launch PID as fallback:
		-- an empty, failed, or non-dsh lsof must never blank serverPID
		-- (orphaned server) or retarget it at an unrelated process.
		-- The server listens on the scraped URL's port (--port 0 above).
		set actualPort to portOfURL(targetURL)
		if actualPort is "" then set actualPort to portText
		set resolvedPID to resolveServerPid(actualPort, serverPID)
		if resolvedPID is not "" then set serverPID to resolvedPID
	end if

	set windowBin to windowAppPath()
	try
		do shell script "/bin/test -x " & quoted form of windowBin
	on error
		display dialog "The DeepSeek Harness window component is missing. Rebuild via ./scripts/build.sh and reinstall." buttons {"OK"} default button "OK" with icon stop
		quit
		return
	end try
	-- A crash orphan may still be around from a killed run; stop it before
	-- launching (same binary path, so the match is exact).
	stopStaleWindows(windowBin)

	-- Chromeless window bundled inside Resources, opened directly on the
	-- target URL (bare or token-bearing): single origin throughout, so no
	-- tab strip, own Dock icon, no browser involved. $! is the window
	-- process itself, which exits with its last window, so the idle cascade
	-- keeps working.
	set chromePID to do shell script windowCommandFor(windowBin, targetURL, wsPath, logFile)
	set windowReady to false
	repeat 10 times
		try
			do shell script "/bin/kill -0 " & chromePID
			set windowReady to true
			exit repeat
		on error
			delay 0.25
		end try
	end repeat

	if windowReady is false then
		display dialog "The DeepSeek Harness window did not open." buttons {"OK"} default button "OK" with icon stop
		quit
	end if
end run

on idle
	if chromePID is not "" then
		try
			do shell script "/bin/kill -0 " & chromePID
		on error
			quit
		end try
	end if

	if serverPID is not "" then
		try
			do shell script "/bin/kill -0 " & serverPID
		on error
			display notification "The DeepSeek Harness server stopped." with title "DeepSeek Harness"
			quit
		end try
	end if

	return 2
end idle

on quit
	if ownsServer and serverPID is not "" then
		do shell script "/bin/kill -TERM " & serverPID & " 2>/dev/null || true"
		repeat 20 times
			try
				do shell script "/bin/kill -0 " & serverPID
				delay 0.25
			on error
				exit repeat
			end try
		end repeat
		-- Only escalate to KILL if TERM did not work, so a dead PID that was
		-- already reused by an unrelated process is never signalled.
		try
			do shell script "/bin/kill -0 " & serverPID
			do shell script "/bin/kill -KILL " & serverPID & " 2>/dev/null || true"
		end try
	end if
	-- The window is left open (as the Chrome app was before it): a crash
	-- orphan is stopped by stopStaleAppWindows at the next launch.
	continue quit
end quit

on serverCheckURLs(portText)
	-- Probe both loopback families (see run handler).
	return {"http://127.0.0.1:" & portText & "/", "http://[::1]:" & portText & "/"}
end serverCheckURLs

on rotateLogIfNeeded(logFile)
	-- Start-only rotation: keep the per-run fresh-log behavior, but avoid
	-- unbounded growth across runs. Files over 5 MB move to logFile + ".1".
	try
		set logSize to (do shell script "/usr/bin/stat -f%z " & quoted form of logFile & " 2>/dev/null || echo 0") as integer
	on error
		return
	end try
	if logSize is greater than 5242880 then
		try
			do shell script "/bin/mv -f " & quoted form of logFile & " " & quoted form of (logFile & ".1") & " 2>/dev/null || true"
		end try
	end if
end rotateLogIfNeeded

on launchCommandFor(wsPath, dshCommand, logFile)
	-- Assemble the background-launch shell line. Grammar is load-bearing:
	-- `do shell script` reads stdout until EOF, so the backgrounded unit must
	-- hold NO pipe file descriptors. With `;`, `&` binds only to the simple
	-- `nohup` command whose stdin/stdout/stderr are all redirected, and the
	-- call returns instantly. With `&&`, `&` would bind to the whole AND-list,
	-- forcing a subshell that holds the pipe open until the server exits, and
	-- `run` would stall forever (Sep 2026 regression: no Chrome, no idle,
	-- orphaned server). NEVER join the cd with && here.
	return "cd " & quoted form of wsPath & "; /usr/bin/nohup " & dshCommand & " >> " & quoted form of logFile & " 2>&1 < /dev/null & echo $!"
end launchCommandFor

on serverURLFromLog(logFile)
	-- Scrape the most recent `dsh web: <url>` startup line. Old servers print
	-- a bare URL, new ones a token URL; the caller probes it verbatim, so no
	-- version check is needed. Returns "" when nothing is found yet.
	try
		set foundURL to do shell script "/usr/bin/grep -o 'dsh web: http[^ ]*' " & quoted form of logFile & " 2>/dev/null | /usr/bin/tail -n 1 | /usr/bin/sed 's/^dsh web: //' || true"
		if foundURL starts with "http" then return foundURL
		return ""
	on error
		return ""
	end try
end serverURLFromLog

on portOfURL(targetURL)
	-- Extract the port from a scraped `dsh web: http://host:PORT/...` URL so
	-- the listener PID can be re-resolved on the server's real (possibly
	-- OS-picked) port. Returns "" when there is nothing to parse.
	try
		return do shell script "/usr/bin/printf %s " & quoted form of targetURL & " | /usr/bin/sed -n -E 's#^https?://[^:/]+:([0-9]+).*#\\1#p' || true"
	on error
		return ""
	end try
end portOfURL

on bareStatusCode(checkURL)
	-- Bare-URL status for the adopted-server token check: 200 is an old
	-- server, 401 is the token fence, 000 is an unreachable race (the caller
	-- treats it as legacy, preserving the old adopt-blindly behavior).
	try
		return do shell script "/usr/bin/curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 --noproxy '*' " & quoted form of checkURL & " || true"
	on error
		return "000"
	end try
end bareStatusCode

on windowAppPath()
	-- The chromeless window ships nested inside this bundle's Resources, so
	-- the launcher installs as one unit. Absent only in hand-built Script
	-- Editor copies, which the caller rejects with a dialog.
	set myBundle to POSIX path of (path to me)
	if myBundle ends with "/" then set myBundle to text 1 thru -2 of myBundle
	return myBundle & "/Contents/Resources/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness"
end windowAppPath

on windowCommandFor(windowBin, targetURL, wsPath, logFile)
	-- Assemble the window launch line: the URL travels as argv (never
	-- interpolated into code). Same load-bearing grammar as
	-- launchCommandFor: `;` + `&` on the simple nohup unit, all fds
	-- redirected, so `do shell script` returns instantly with $! -- and $!
	-- is the window process itself, which exits with its last window.
	return "cd " & quoted form of wsPath & "; /usr/bin/nohup " & quoted form of windowBin & " " & quoted form of targetURL & " >> " & quoted form of logFile & " 2>&1 < /dev/null & echo $!"
end windowCommandFor

on stopStaleWindows(windowBin)
	-- A crash orphan (same binary path) is stopped before launching, TERM
	-- then KILL. The match pattern brackets its first character (classic
	-- self-exclusion): pkill/pgrep cmdlines carry the bracketed form, which
	-- the regex never matches, so the invoking shells can neither kill
	-- themselves nor wedge the wait loop below. Absolute paths only, so the
	-- bracketed "/" is always a safe literal.
	if windowBin does not start with "/" then return
	set matchPattern to "[" & text 1 of windowBin & "]" & text 2 thru -1 of windowBin
	try
		do shell script "/usr/bin/pkill -TERM -f -- " & quoted form of matchPattern & " 2>/dev/null || true"
	end try
	repeat 10 times
		try
			do shell script "/usr/bin/pgrep -f -- " & quoted form of matchPattern & " >/dev/null && exit 1 || exit 0"
			exit repeat
		on error
			delay 0.5
		end try
	end repeat
	try
		do shell script "/usr/bin/pkill -KILL -f -- " & quoted form of matchPattern & " 2>/dev/null || true"
	end try
end stopStaleWindows

on dshPidAmongListeners(listenerPIDs)
	-- Return the first listener PID whose command line is the dsh server,
	-- or "" when none matches. Accepts the npx form (@deepseek-ai/dsh) or
	-- the binary form (dsh web). Word boundaries keep this strict: a mere
	-- mention of dsh in some other program's command line must not be
	-- mistaken for the server. Checks every listener (IPv4/IPv6 doubles).
	set matchedPID to ""
	repeat with candidatePID in paragraphs of listenerPIDs
		if (candidatePID as text) is not "" then
			try
				-- -ww avoids truncating long mise/npx command lines.
				do shell script "/bin/ps -p " & candidatePID & " -ww -o command= | /usr/bin/grep -E -q '(^|[ /])dsh( |$| web)|@deepseek-ai/dsh'"
				set matchedPID to candidatePID as text
				exit repeat
			end try
		end if
	end repeat
	return matchedPID
end dshPidAmongListeners

on resolveServerPid(portText, launchPID)
	-- Re-read the listeners for a freshly started server and return the PID
	-- to track. Prefers the known launch PID when it is still listening
	-- (no PID-reuse window, no fork-ordering guess); otherwise falls back to
	-- the first dsh match among all listeners. Returns "" when nothing
	-- usable is found so the caller keeps its fallback and never blanks
	-- serverPID (orphaned server) or retargets an unrelated process.
	set listenerPIDs to ""
	try
		set listenerPIDs to do shell script "/usr/sbin/lsof -nP -tiTCP:" & portText & " -sTCP:LISTEN 2>/dev/null || true"
	end try
	if listenerPIDs is "" then return ""
	if launchPID is not "" then
		repeat with candidatePID in paragraphs of listenerPIDs
			if (candidatePID as text) is not "" and (candidatePID as text) = (launchPID as text) then
				return launchPID as text
			end if
		end repeat
	end if
	return dshPidAmongListeners(listenerPIDs)
end resolveServerPid

on homeDirectory()
	-- Prefer $HOME so tests can run hermetically (HOME=$TMP/fakehome);
	-- `path to home folder` ignores $HOME. Identical in normal use.
	try
		set envHome to do shell script "/usr/bin/printenv HOME || true"
		if envHome is not "" and envHome starts with "/" then
			if envHome is not "/" and envHome ends with "/" then
				set envHome to text 1 thru -2 of envHome
			end if
			return envHome
		end if
	end try
	set homePath to POSIX path of (path to home folder)
	if homePath is not "/" and homePath ends with "/" then
		set homePath to text 1 thru -2 of homePath
	end if
	return homePath
end homeDirectory

on workspacePath()
	return homeDirectory() & "/.dsh/workspace"
end workspacePath

on logFilePath()
	return homeDirectory() & "/Library/Logs/DeepSeek Harness.log"
end logFilePath

on configFilePath()
	-- Test hook: point the launcher at a fixture config without touching ~/.
	try
		set configOverride to do shell script "/usr/bin/printenv DEEPSEEK_HARNESS_CONFIG || true"
		if configOverride is not "" then return configOverride
	end try
	return homeDirectory() & "/" & configRelPath
end configFilePath

on expandedPath(thePath)
	if thePath is "~" then
		return homeDirectory()
	else if thePath starts with "~/" then
		return homeDirectory() & text 2 thru -1 of thePath
	end if
	return thePath
end expandedPath

on unquoted(theValue)
	set trimmed to theValue
	-- An empty quoted pair is empty, not a literal '""': text 2 thru -2 of a
	-- 2-char string does not yield "" in AppleScript, so handle it directly.
	if trimmed is "\"\"" then
		return ""
	end if
	if trimmed starts with "\"" and trimmed ends with "\"" and (length of trimmed) > 2 then
		set trimmed to text 2 thru -2 of trimmed
	end if
	return trimmed
end unquoted

on configValueFor(keyName)
	set cfg to configFilePath()
	try
		do shell script "/bin/test -f " & quoted form of cfg
	on error
		return ""
	end try
	try
		-- Exact key match ($1 == key): SERVER_PORT_EXTRA must not match
		-- SERVER_PORT. Last occurrence wins; values may contain '='.
		-- Outer [space/tab/CR] trimmed so 'KEY=  ~/x  ' and CRLF files work.
		-- Key syntax stays strict (^KEY=, no export/spaces) by design.
		-- LC_ALL=C pins byte-wise matching so a UTF-8 BOM never equals
		-- a bare key (macOS awk strips BOM under en_US.UTF-8).
		set rawVal to do shell script "LC_ALL=C /usr/bin/awk -F= -v key=" & quoted form of keyName & " '$1 == key { v = substr($0, length($1) + 2) } END { gsub(/^[ \\t\\r]+|[ \\t\\r]+$/, \"\", v); print v }' " & quoted form of cfg & " || true"
	on error
		return ""
	end try
	if rawVal is "" then return ""
	set rawVal to unquoted(rawVal)
	if rawVal is "" then return ""
	-- A quoted blank (KEY="   ") counts as unset, like KEY="".
	try
		set blankCheck to do shell script "/usr/bin/printf %s " & quoted form of rawVal & " | /usr/bin/tr -d '[:space:]'"
		if blankCheck is "" then return ""
	on error
		return ""
	end try
	return expandedPath(rawVal)
end configValueFor

on effectiveServerPort()
	set rawPort to configValueFor("SERVER_PORT")
	if rawPort is not "" then
		try
			set trimmed to do shell script "/usr/bin/printf %s " & quoted form of rawPort & " | /usr/bin/tr -d '[:space:]'"
			set numPort to trimmed as integer
			if numPort > 0 and numPort < 65536 then return numPort
		end try
	end if
	return serverPort
end effectiveServerPort

on effectiveWorkspacePath()
	set customPath to configValueFor("WORKSPACE")
	if customPath is not "" then return customPath
	return workspacePath()
end effectiveWorkspacePath

on effectiveLogFilePath()
	set customLog to configValueFor("LOG_FILE")
	if customLog is not "" then return customLog
	return logFilePath()
end effectiveLogFilePath

on effectiveDshCommand()
	set customCommand to configValueFor("DSH_COMMAND")
	if customCommand is not "" then return customCommand
	return do shell script "if [ -x /opt/homebrew/bin/mise ]; then echo '/opt/homebrew/bin/mise exec -- dsh web --no-open'; elif [ -x /usr/local/bin/mise ]; then echo '/usr/local/bin/mise exec -- dsh web --no-open'; elif /usr/bin/command -v mise >/dev/null 2>&1; then echo 'mise exec -- dsh web --no-open'; else echo 'npx -y @deepseek-ai/dsh web --no-open'; fi"
end effectiveDshCommand
