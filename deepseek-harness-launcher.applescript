property serverPID : ""
property chromePID : ""
property ownsServer : false

property serverURL : "http://127.0.0.1:3080/"
property workspacePath : "/Users/jameschang/.dsh/workspace"
property logPath : "/Users/jameschang/Library/Logs/DeepSeek Harness.log"
property chromeAppPath : "/Users/jameschang/Applications/Chrome Apps.localized/DeepSeek Harness.app"
property chromeLoaderPath : "/Users/jameschang/Applications/Chrome Apps.localized/DeepSeek Harness.app/Contents/MacOS/app_mode_loader"

on run
	set serverPID to ""
	set chromePID to ""
	set ownsServer to false

	set existingPID to do shell script "/usr/sbin/lsof -nP -tiTCP:3080 -sTCP:LISTEN 2>/dev/null | /usr/bin/head -n 1 || true"
	if existingPID is not "" then
		set existingCommand to do shell script "/bin/ps -p " & existingPID & " -o command="
		if existingCommand does not contain "@deepseek-ai/dsh" then
			display dialog "Port 3080 is already in use by another program." buttons {"OK"} default button "OK" with icon stop
			quit
			return
		end if
	else
		do shell script "/bin/mkdir -p " & quoted form of workspacePath
		set launchCommand to "cd " & quoted form of workspacePath & "; /usr/bin/nohup /opt/homebrew/bin/mise exec -- dsh web --no-open >> " & quoted form of logPath & " 2>&1 < /dev/null & echo $!"
		set serverPID to do shell script launchCommand
		set ownsServer to true

		set serverReady to false
		repeat 60 times
			try
				do shell script "/usr/bin/curl --fail --silent --max-time 1 " & quoted form of serverURL & " >/dev/null"
				set serverReady to true
				exit repeat
			on error
				delay 0.5
			end try
		end repeat

		if serverReady is false then
			display dialog "DeepSeek Harness did not start. See " & logPath buttons {"OK"} default button "OK" with icon stop
			quit
			return
		end if

		set serverPID to do shell script "/usr/sbin/lsof -nP -tiTCP:3080 -sTCP:LISTEN | /usr/bin/head -n 1"
	end if

	do shell script "/usr/bin/open " & quoted form of chromeAppPath

	repeat 40 times
		set chromePID to do shell script "/bin/ps -axo pid=,command= | /usr/bin/grep -F " & quoted form of chromeLoaderPath & " | /usr/bin/grep -v grep | /usr/bin/awk 'NR == 1 { print $1 }' || true"
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
