#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Quit Apps
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ⏹️

tell application "System Events" to set the visible of every process to true

set base_white_list to {"Finder", "Terminal", "Google Chrome", "Todoist", "Notion", "Google Chat", "Slack", "dbeaver", "Code", "Raycast", "Microsoft Remote Desktop", "Kindle", "Arc", "Obsidian", "Cursor"}

# karabiner.jsonのショートカットで起動対象となっている.appも保護対象に加える
set karabiner_apps to {}
try
    set shell_output to do shell script "/usr/bin/jq -r '.. | objects | .shell_command? // empty' ~/.config/karabiner/karabiner.json | /usr/bin/grep -oE \"/[^/']+\\\\.app'\" | /usr/bin/sed -E \"s|^/||; s|\\\\.app'$||\" | /usr/bin/sort -u"
    set AppleScript's text item delimiters to return
    set karabiner_apps to every text item of shell_output
    set AppleScript's text item delimiters to ""
end try

set white_list to base_white_list & karabiner_apps

try
    tell application "Finder"
        set process_list to the displayed name of every process whose visible is true
    end tell
    repeat with i from 1 to (number of items in process_list)
        set this_process to item i of the process_list
        if this_process is not in white_list then
            # log "終了対象アプリ：" & this_process
            tell application this_process to quit
        end if
    end repeat
    tell application "Finder" to close every window
on error
    tell the current application to display dialog "An error has occurred!" & return & "This script will now quit" buttons {"Quit"} default button 1 with icon 0
end try
