#!/usr/bin/env bash
# 稼働中の herdr session をすべて正常停止し、レイアウトを session.json に保存させる。
#
# OS のシャットダウンに任せると、pane の shell が server より先に終了した場合に
# server が「workspace が空」と判断して session.json を消去し、次回起動時に
# レイアウトが復元されない（herdr issue #5349）。シャットダウン前にこの script で
# 先に止めておくと、pane が生きている状態で保存される。
#
# default session は `herdr server stop`、named session は `herdr session stop <name>`
# で止める。pane 内のプロセスは終了する（復元されるのはレイアウトと agent の会話）。

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/path-bootstrap.sh"

herdr session list --json |
	jq -r '.sessions[] | select(.running) | if .default then "" else .name end' |
	while IFS= read -r name; do
		if [[ -z $name ]]; then
			herdr server stop
		else
			herdr session stop "$name"
		fi
	done
