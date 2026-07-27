#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Move mouse to center
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ↖

tell application "System Events"
	set frontApp to first application process whose frontmost is true
	set frontWindow to first window of frontApp
	set windowPosition to position of frontWindow
	set windowSize to size of frontWindow
	set windowWidth to item 1 of windowSize
	set windowHeight to item 2 of windowSize
	set centerX to (item 1 of windowPosition) + (windowWidth / 2)
	set centerY to (item 2 of windowPosition) + (windowHeight / 2)

	set mousePos to {centerX, centerY}

end tell

use framework "Foundation"
use framework "CoreGraphics"

set cursorPoint to current application's NSMakePoint(centerX, centerY)
current application's CGWarpMouseCursorPosition(cursorPoint)
