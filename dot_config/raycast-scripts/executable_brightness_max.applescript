#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title brightness max
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔆

tell application "System Events"
    repeat 16 times
        key code 144 -- increase
        -- key code 145 -- reduce
    end repeat
end tell
