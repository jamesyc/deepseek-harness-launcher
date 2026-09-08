property serverPID : ""
property chromePID : ""
property ownsServer : false
property resolvedChromeAppPath : ""

property serverPort : 3080
property chromeAppName : "DeepSeek Harness.app"

on run
	set serverPID to ""
	set chromePID to ""
	set ownsServer to false

	set portText to (serverPort as text)
	set wsPath to workspacePath()
	set logFile to logFilePath()
	set checkURL to serverURL()

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
		set dshCommand to do shell script "if [ -x /opt/homebrew/bin/mise ]; then echo '/opt/homebrew/bin/mise exec -- dsh web --no-open'; elif [ -x /usr/local/bin/mise ]; then echo '/usr/local/bin/mise exec -- dsh web --no-open'; elif /usr/bin/command -v mise >/dev/null 2>&1; then echo 'mise exec -- dsh web --no-open'; else echo 'npx -y @deepseek-ai/dsh web --no-open'; fi"
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

	set chromeApp to findChromeApp()
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

on serverURL()
	return "http://127.0.0.1:" & (serverPort as text) & "/"
end serverURL

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
