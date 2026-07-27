#!/opt/homebrew/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Path win2mac
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🍎
# @raycast.argument1 { "type": "text", "placeholder": "path" }

echo ${@}

convert() {
  path=$1
  path=smb:${path//\\//}
  echo $path
  return 0
}

for f in "$@"; do
  path="$(convert $f)"

  echo $path
  open $path
done
