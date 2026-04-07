on target_process(targetPid)
	tell application "System Events"
		return first process whose unix id is targetPid
	end tell
end target_process

on wait_for_process(targetPid, appName, timeoutSeconds)
	tell application "System Events"
		repeat with attempt from 1 to (timeoutSeconds * 4)
			if exists (first process whose unix id is targetPid) then
				return
			end if
			delay 0.25
		end repeat
	end tell
	error "Timed out waiting for process " & appName & " pid " & targetPid
end wait_for_process

on wait_for_window(targetPid, appName, windowTitle, timeoutSeconds)
	tell application "System Events"
		tell my target_process(targetPid)
			repeat with attempt from 1 to (timeoutSeconds * 4)
				if windowTitle is missing value then
					if (exists window 1) then
						return
					end if
				else
					if exists window windowTitle then
						return
					end if
				end if
				delay 0.25
			end repeat
		end tell
	end tell

	if windowTitle is missing value then
		tell application "System Events"
			if exists (first process whose unix id is targetPid) then
				tell my target_process(targetPid)
					set windowNames to name of every window
					set windowCount to count of windows
					set processName to name
					set processFrontmost to frontmost
					set processBackgroundOnly to background only
				end tell
				error "Timed out waiting for a window in " & appName & " pid " & targetPid & ". Process name: " & processName & ". Frontmost: " & processFrontmost & ". Background only: " & processBackgroundOnly & ". Window count: " & windowCount & ". Visible windows: " & (windowNames as text)
			end if
		end tell
		error appName & " pid " & targetPid & " exited before showing a window"
	end if

	error "Timed out waiting for window " & windowTitle
end wait_for_window

on wait_for_window_to_close(targetPid, appName, windowTitle, timeoutSeconds)
	tell application "System Events"
		tell my target_process(targetPid)
			repeat with attempt from 1 to (timeoutSeconds * 4)
				if not (exists window windowTitle) then
					return
				end if
				delay 0.25
			end repeat
		end tell
	end tell

	error "Timed out waiting for window " & windowTitle & " to close"
end wait_for_window_to_close

on click_menu_item(targetPid, menuName, itemName)
	tell application "System Events"
		tell my target_process(targetPid)
			click menu item itemName of menu menuName of menu bar 1
		end tell
	end tell
end click_menu_item

on run argv
	if (count of argv) is less than 2 then
		error "Expected app name and pid arguments"
	end if

	set appName to item 1 of argv
	set targetPid to (item 2 of argv) as integer

	tell application "System Events"
		if UI elements enabled is false then
			error "UI scripting is disabled. Enable System Events accessibility access to run the interactive macOS smoke test."
		end if
	end tell

	my wait_for_process(targetPid, appName, 30)
	tell application appName to activate
	delay 1

	tell application "System Events"
		tell my target_process(targetPid)
			set frontmost to true
		end tell
	end tell

	my wait_for_window(targetPid, appName, missing value, 30)
	my click_menu_item(targetPid, "Settings", "Configure Machine...")
	my wait_for_window(targetPid, appName, "Configure Arculator", 20)

	tell application "System Events"
		tell my target_process(targetPid)
			click button "Cancel" of window "Configure Arculator"
		end tell
	end tell

	my wait_for_window_to_close(targetPid, appName, "Configure Arculator", 20)
	my click_menu_item(targetPid, "File", "Hard Reset")
	delay 1
	my click_menu_item(targetPid, "File", "Exit")
end run
