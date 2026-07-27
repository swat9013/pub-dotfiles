tell application "System Events" to set the visible of every process to true

try
    tell application "Finder"
        set process_list to the displayed name of every process whose visible is true
        -- set process_list to the name of every process whose visible is true
    end tell
    repeat with i from 1 to (number of items in process_list)
        set this_process to item i of the process_list
        log this_process
    end repeat
on error
    tell the current application to display dialog "An error has occurred!" & return & "This script will now quit" buttons {"Quit"} default button 1 with icon 0
end try
