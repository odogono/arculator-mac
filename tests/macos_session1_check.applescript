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
					if (exists window 1) then return
				else
					if exists window windowTitle then return
				end if
				delay 0.25
			end repeat
		end tell
	end tell
	error "Timed out waiting for window " & windowTitle & " in " & appName
end wait_for_window

on wait_for_window_to_close(targetPid, windowTitle, timeoutSeconds)
	tell application "System Events"
		tell my target_process(targetPid)
			repeat with attempt from 1 to (timeoutSeconds * 4)
				if not (exists window windowTitle) then return
				delay 0.25
			end repeat
		end tell
	end tell
	error "Timed out waiting for window " & windowTitle & " to close"
end wait_for_window_to_close

on wait_for_modal_window(targetPid, expectedTextFieldCount, expectedPopupCount, timeoutSeconds)
	tell application "System Events"
		tell my target_process(targetPid)
			repeat with attempt from 1 to (timeoutSeconds * 4)
				repeat with windowIndex from 1 to (count of windows)
					set candidate to window windowIndex
					set candidateName to ""
					set textFieldCount to 0
					set popupCount to 0
					try
						set candidateName to name of candidate
					end try
					try
						set textFieldCount to count of text fields of candidate
					end try
					try
						set popupCount to count of pop up buttons of candidate
					end try
					if candidateName is "" and textFieldCount is expectedTextFieldCount and popupCount is expectedPopupCount then
						return
					end if
				end repeat
				delay 0.25
			end repeat
		end tell
	end tell
	error "Timed out waiting for unnamed modal window"
end wait_for_modal_window

on click_menu_item(targetPid, menuName, itemName)
	tell application "System Events"
		tell my target_process(targetPid)
			click menu item itemName of menu menuName of menu bar 1
		end tell
	end tell
end click_menu_item

on activate_app(appName, targetPid)
	tell application appName to activate
	delay 1
	tell application "System Events"
		tell my target_process(targetPid)
			set frontmost to true
		end tell
	end tell
end activate_app

on set_prompt_value(targetPid, textValue)
	tell application "System Events"
		tell my target_process(targetPid)
			set value of text field 1 of window 1 to textValue
			click button 2 of window 1
		end tell
	end tell
end set_prompt_value

on select_popup_item(targetPid, windowTitle, popupIndex, itemName)
	tell application "System Events"
		tell my target_process(targetPid)
			tell window windowTitle
				click pop up button popupIndex
				delay 0.3
				click menu item itemName of menu 1 of pop up button popupIndex
			end tell
		end tell
	end tell
end select_popup_item

on select_scroll_popup_item(targetPid, windowTitle, scrollAreaIndex, popupIndex, itemName)
	repeat with attempt from 1 to 3
		tell application "System Events"
			tell my target_process(targetPid)
				tell scroll area scrollAreaIndex of window windowTitle
					click pop up button popupIndex
					delay 0.3
					click menu item itemName of menu 1 of pop up button popupIndex
					delay 0.5
					if (value of pop up button popupIndex as text) is itemName then return
				end tell
			end tell
		end tell
	end repeat
	error "Failed to select " & itemName & " in " & windowTitle
end select_scroll_popup_item

on exercise_session1(appName, targetPid, createdName, renamedName, copiedName)
	my wait_for_process(targetPid, appName, 30)
	my activate_app(appName, targetPid)
	my wait_for_window(targetPid, appName, "Select Configuration", 30)
	log "stage=create"

	tell application "System Events"
		tell my target_process(targetPid)
			click button "New" of window "Select Configuration"
		end tell
	end tell
	my wait_for_modal_window(targetPid, 1, 0, 20)
	my set_prompt_value(targetPid, createdName)

	my wait_for_modal_window(targetPid, 0, 1, 20)
	tell application "System Events"
		tell my target_process(targetPid)
			tell window 1
				click pop up button 1
				delay 0.3
				click menu item "A3000" of menu 1 of pop up button 1
				click button 2
			end tell
		end tell
	end tell

	my wait_for_window(targetPid, appName, "Configure Arculator", 20)
	my select_scroll_popup_item(targetPid, "Configure Arculator", 1, 3, "2 MB")
	tell application "System Events"
		tell my target_process(targetPid)
			click button "OK" of window "Configure Arculator"
		end tell
	end tell
	my wait_for_window_to_close(targetPid, "Configure Arculator", 20)
	my activate_app(appName, targetPid)
	log "stage=rename"

	tell application "System Events"
		tell my target_process(targetPid)
			click button "Rename" of window "Select Configuration"
		end tell
	end tell
	my wait_for_modal_window(targetPid, 1, 0, 20)
	my set_prompt_value(targetPid, renamedName)
	my activate_app(appName, targetPid)
	log "stage=copy"

	tell application "System Events"
		tell my target_process(targetPid)
			click button "Copy" of window "Select Configuration"
		end tell
	end tell
	my wait_for_modal_window(targetPid, 1, 0, 20)
	my set_prompt_value(targetPid, copiedName)
	my activate_app(appName, targetPid)
	log "stage=delete"

	tell application "System Events"
		tell my target_process(targetPid)
			click button "Delete" of window "Select Configuration"
		end tell
	end tell
	my wait_for_modal_window(targetPid, 0, 0, 20)
	tell application "System Events"
		tell my target_process(targetPid)
			click button 2 of window 1
		end tell
	end tell
	my activate_app(appName, targetPid)
	log "stage=open"

	tell application "System Events"
		tell my target_process(targetPid)
			click button "Open" of window "Select Configuration"
		end tell
	end tell

	my wait_for_window_to_close(targetPid, "Select Configuration", 20)
	my wait_for_window(targetPid, appName, missing value, 20)
	delay 1
	my click_menu_item(targetPid, "File", "Exit")
end exercise_session1

on exit_after_launch(appName, targetPid)
	my wait_for_process(targetPid, appName, 30)
	my activate_app(appName, targetPid)
	my wait_for_window(targetPid, appName, missing value, 30)
	delay 1
	my click_menu_item(targetPid, "File", "Exit")
end exit_after_launch

on run argv
	if (count of argv) < 3 then
		error "Expected mode, app name, and pid arguments"
	end if

	set modeName to item 1 of argv
	set appName to item 2 of argv
	set targetPid to (item 3 of argv) as integer

	tell application "System Events"
		if UI elements enabled is false then
			error "UI scripting is disabled."
		end if
	end tell

	if modeName is "exercise" then
		if (count of argv) is not 6 then
			error "Exercise mode expects created, renamed, and copied config names"
		end if
		my exercise_session1(appName, targetPid, item 4 of argv, item 5 of argv, item 6 of argv)
	else if modeName is "exit_after_launch" then
		my exit_after_launch(appName, targetPid)
	else
		error "Unknown mode: " & modeName
	end if
end run
