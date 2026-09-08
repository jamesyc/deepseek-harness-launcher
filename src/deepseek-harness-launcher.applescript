property serverPID : ""
property chromePID : ""
property ownsServer : false
property resolvedChromeAppPath : ""

property serverPort : 3080
property chromeAppName : "DeepSeek Harness.app"
property configRelPath : ".config/deepseek-harness-launcher/config"

on run
	set serverPID to ""
	set chromePID to ""
	set ownsServer to false

	set activePort to effectiveServerPort()
	set portText to (activePort as text)
	set wsPath to effectiveWorkspacePath()
	set logFile to effectiveLogFilePath()
	set checkURL to "http://127.0.0.1:" & portText & "/"

	set existingPID to do shell script "/usr/sbin/lsof -nP -tiTCP:" & portText & " -sTCP:LISTEN 2>/dev/null | /usr/bin/head -n 1 || true"
	if existingPID is not "" then
		set existingCommand to do shell script "/bin/ps -p " & existingPID & " -o command="
		if existingCommand does not contain "@deepseek-ai/dsh" then
			display dialog "Port " & portText & " is already in use by another program." buttons {"OK"} default button "OK" with icon stop
			quit
			return
		end if
	else
		do shell script "/bin/mkdir -p " & quoted form of wsPath
		set dshCommand to effectiveDshCommand()
		set launchCommand to "cd " & quoted form of wsPath & "; /usr/bin/nohup " & dshCommand & " >> " & quoted form of logFile & " 2>&1 < /dev/null & echo $!"
		set serverPID to do shell script launchCommand
		set ownsServer to true

		set serverReady to false
		repeat 60 times
			try
				do shell script "/usr/bin/curl --fail --silent --max-time 1 " & quoted form of checkURL & " >/dev/null"
				set serverReady to true
				exit repeat
			on error
				delay 0.5
			end try
		end repeat

		if serverReady is false then
			display dialog "DeepSeek Harness did not start. See " & logFile buttons {"OK"} default button "OK" with icon stop
			quit
			return
		end if

		set serverPID to do shell script "/usr/sbin/lsof -nP -tiTCP:" & portText & " -sTCP:LISTEN | /usr/bin/head -n 1"
	end if

	set chromeApp to effectiveChromeApp()
	if chromeApp is "" then
		quit
		return
	end if
	set loaderPath to chromeApp & "/Contents/MacOS/app_mode_loader"

	do shell script "/usr/bin/open " & quoted form of chromeApp

	repeat 40 times
		set chromePID to do shell script "/bin/ps -axo pid=,command= | /usr/bin/grep -F " & quoted form of loaderPath & " | /usr/bin/grep -v grep | /usr/bin/awk 'NR == 1 { print $1 }' || true"
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

	if ownsServer and serverPID is not "" then
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
		do shell script "/bin/kill -KILL " & serverPID & " 2>/dev/null || true"
	end if
	continue quit
end quit

on homeDirectory()
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
	if trimmed starts with "\"" and trimmed ends with "\"" and (length of trimmed) ≥ 2 then
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
		set rawVal to do shell script "/usr/bin/grep -E '^" & keyName & "=' " & quoted form of cfg & " | /usr/bin/tail -n 1 | /usr/bin/cut -d= -f2- || true"
	on error
		return ""
	end try
	if rawVal is "" then return ""
	set rawVal to unquoted(rawVal)
	if rawVal is "" then return ""
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

on findChromeApp()
	if resolvedChromeAppPath is not "" then
		try
			do shell script "/bin/test -d " & quoted form of resolvedChromeAppPath
			return resolvedChromeAppPath
		end try
	end if

	set homeDir to homeDirectory()
	set candidates to {homeDir & "/Applications/" & chromeAppName, homeDir & "/Applications/Chrome Apps.localized/" & chromeAppName, "/Applications/" & chromeAppName, "/Applications/Chrome Apps.localized/" & chromeAppName}
	repeat with candidate in candidates
		try
			do shell script "/bin/test -d " & quoted form of candidate
			set resolvedChromeAppPath to candidate as text
			return resolvedChromeAppPath
		end try
	end repeat

	try
		set chosenApp to choose file of type {"com.apple.application-bundle"} with prompt "Locate your " & chromeAppName & " Chrome app"
		set resolvedChromeAppPath to POSIX path of chosenApp
		if resolvedChromeAppPath ends with "/" then
			set resolvedChromeAppPath to text 1 thru -2 of resolvedChromeAppPath
		end if
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
