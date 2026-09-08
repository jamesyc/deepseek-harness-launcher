property serverPID : ""
property chromePID : ""
property ownsServer : false
property resolvedChromeAppPath : ""

property serverPort : 3080
property chromeAppName : "DeepSeek Harness.app"
property configRelPath : ".config/deepseek-harness-launcher/config"
property chromeCacheRelPath : "Library/Application Support/DeepSeek Harness Launcher/ChromeAppPath"

on run
	set serverPID to ""
	set chromePID to ""
	set ownsServer to false

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
	else
		do shell script "/bin/mkdir -p " & quoted form of wsPath
		-- Fresh log per run so a failure dialog shows this attempt, not history.
		-- Rotate a large previous log to .1 first (single backup, 5 MB threshold).
		set logDir to do shell script "/usr/bin/dirname " & quoted form of logFile
		do shell script "/bin/mkdir -p " & quoted form of logDir
		rotateLogIfNeeded(logFile)
		do shell script ": > " & quoted form of logFile & " || true"
		set dshCommand to effectiveDshCommand()
		set launchCommand to launchCommandFor(wsPath, dshCommand, logFile)
		-- Must return instantly; a hang here stalls run forever (no Chrome,
		-- no idle, no quit handling). Guaranteed by launchCommandFor's shell
		-- grammar -- see its comment. (Note: `with timeout` does NOT bound
		-- `do shell script`, so it cannot guard this call.)
		set serverPID to do shell script launchCommand
		set ownsServer to true

		set serverReady to false
		repeat 60 times
			try
				-- Probe IPv4 then IPv6: lsof matches listeners on either
				-- family, but curl to 127.0.0.1 fails if dsh bound ::1 only.
				do shell script "/usr/bin/curl --fail --silent --max-time 1 " & quoted form of item 1 of checkURLs & " >/dev/null || /usr/bin/curl --fail --silent --max-time 1 " & quoted form of item 2 of checkURLs & " >/dev/null"
				set serverReady to true
				exit repeat
			on error
				delay 0.5
			end try
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
		set resolvedPID to resolveServerPid(portText, serverPID)
		if resolvedPID is not "" then set serverPID to resolvedPID
	end if

	set chromeApp to effectiveChromeApp()
	if chromeApp is "" then
		quit
		return
	end if
	set loaderPath to chromeLoaderPathFor(chromeApp)
	-- NOTE (verified Sep 2026): app_mode_loader persists while the Chrome app
	-- window is open and exits a few seconds after quit, so idle may take one
	-- extra cycle to notice. Do not "fix" by tracking the main Chrome process.

	do shell script "/usr/bin/open " & quoted form of chromeApp

	repeat 40 times
		set chromePID to chromePidForLoader(loaderPath)
		if chromePID is not "" then exit repeat
		delay 0.25
	end repeat

	if chromePID is "" then
		display dialog "The DeepSeek Harness Chrome app did not open." buttons {"OK"} default button "OK" with icon stop
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

on chromeCacheFile()
	-- Test hook: redirect the picker cache to a temp file.
	try
		set cacheOverride to do shell script "/usr/bin/printenv DEEPSEEK_HARNESS_CACHE || true"
		if cacheOverride is not "" then return cacheOverride
	end try
	return homeDirectory() & "/" & chromeCacheRelPath
end chromeCacheFile

on readChromeCache()
	set cacheFile to chromeCacheFile()
	try
		do shell script "/bin/test -f " & quoted form of cacheFile
	on error
		return ""
	end try
	try
		set cached to do shell script "/usr/bin/head -n 1 " & quoted form of cacheFile & " 2>/dev/null | /usr/bin/tr -d '\\r\\n' || true"
		if cached is "" then return ""
		return cached
	on error
		return ""
	end try
end readChromeCache

on writeChromeCache(appPath)
	if appPath is "" then return
	set cacheFile to chromeCacheFile()
	try
		set cacheDir to do shell script "/usr/bin/dirname " & quoted form of cacheFile
		do shell script "/bin/mkdir -p " & quoted form of cacheDir & "; /usr/bin/printf %s " & quoted form of appPath & " > " & quoted form of cacheFile & "; /bin/chmod 600 " & quoted form of cacheFile & " || true"
	end try
end writeChromeCache

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

on effectiveChromeApp()
	set customApp to configValueFor("CHROME_APP")
	if customApp is not "" then
		try
			do shell script "/bin/test -d " & quoted form of customApp
			return customApp
		on error
			display dialog "Configured Chrome app was not found (" & customApp & "). Falling back to search." buttons {"OK"} default button "OK" with icon note
		end try
	end if
	return findChromeApp()
end effectiveChromeApp

on chromeLoaderPathFor(chromeApp)
	-- Read the real executable name instead of assuming app_mode_loader,
	-- which may change across Chrome versions.
	try
		set execName to do shell script "/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' " & quoted form of (chromeApp & "/Contents/Info.plist")
		if execName is "" then error "empty executable name"
		return chromeApp & "/Contents/MacOS/" & execName
	on error
		return chromeApp & "/Contents/MacOS/app_mode_loader"
	end try
end chromeLoaderPathFor

on chromePidForLoader(loaderPath)
	-- Exact executable match: the ps command must equal the loader path or
	-- start with it followed by a space (args). A plain substring match
	-- would confuse /Foo.app/... with /Foo2.app/.... Single awk, no grep,
	-- so no grep -v self-match dance and no SIGPIPE pipefail hazard.
	try
		return do shell script "/bin/ps -axww -o pid=,command= | /usr/bin/awk -v target=" & quoted form of loaderPath & " '{ pid = $1; sub(/^ *[^ ]+ +/, \"\"); cmd = $0; if (cmd == target || substr(cmd, 1, length(target) + 1) == target \" \") { print pid; exit } }' || true"
	on error
		return ""
	end try
end chromePidForLoader

on findChromeApp()
	-- 1. File cache: survives reinstalls (unlike the legacy main.scpt property).
	set cachedPath to readChromeCache()
	if cachedPath is not "" then
		try
			do shell script "/bin/test -d " & quoted form of cachedPath
			set resolvedChromeAppPath to cachedPath
			return cachedPath
		end try
	end if

	-- 2. Legacy in-memory property: migrate pre-file-cache picks forward.
	if resolvedChromeAppPath is not "" then
		try
			do shell script "/bin/test -d " & quoted form of resolvedChromeAppPath
			writeChromeCache(resolvedChromeAppPath)
			return resolvedChromeAppPath
		end try
	end if

	set homeDir to homeDirectory()
	set candidates to {homeDir & "/Applications/" & chromeAppName, homeDir & "/Applications/Chrome Apps.localized/" & chromeAppName, "/Applications/" & chromeAppName, "/Applications/Chrome Apps.localized/" & chromeAppName}
	repeat with candidate in candidates
		try
			do shell script "/bin/test -d " & quoted form of candidate
			set resolvedChromeAppPath to candidate as text
			writeChromeCache(resolvedChromeAppPath)
			return resolvedChromeAppPath
		end try
	end repeat

	try
		set chosenApp to choose file of type {"com.apple.application-bundle"} with prompt "Locate your " & chromeAppName & " Chrome app"
		set resolvedChromeAppPath to POSIX path of chosenApp
		if resolvedChromeAppPath ends with "/" then
			set resolvedChromeAppPath to text 1 thru -2 of resolvedChromeAppPath
		end if
		writeChromeCache(resolvedChromeAppPath)
		return resolvedChromeAppPath
	on error errorMessage number errorNumber
		if errorNumber is -128 then
			display dialog "No Chrome app selected. Quitting." buttons {"OK"} default button "OK" with icon note
		else
			display dialog "Could not locate the Chrome app: " & errorMessage buttons {"OK"} default button "OK" with icon stop
		end if
		return ""
	end try
end findChromeApp
