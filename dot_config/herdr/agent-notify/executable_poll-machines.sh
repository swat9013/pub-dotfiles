#!/usr/bin/env bash
# 接続先 machine（herdr の saved SSH machine）の agent を 1 回見て、done / idle / blocked に
# 変わったものを macOS 通知する。Hammerspoon が定期的に起動する。
#
# herdr plugin の event hook（notify.sh）は手元の server の agent しか受けないため、
# machine の agent は `herdr --machine` で見に行く。
# 通知を押すと machine 側でその pane にフォーカスし、Ghostty を前面に出す。表示中の
# machine の切り替えは herdr の CLI に口が無いので、別の machine を表示中なら手で切り替える。
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

herdr_bin=$(command -v herdr)
sep=$'\x1f'

main() {
	local id label selected
	while IFS=$sep read -r id label selected; do
		poll_machine "$id" "$label" "$selected" || true
	done < <(herdr machine list --json | jq -r --arg s "$sep" \
		'.[] | select(.enabled) | [.id, .label, .selected] | join($s)')
}

poll_machine() {
	local id=$1 label=$2 selected=$3
	local agents workspaces
	# </dev/null: 呼び出し元の stdin（machine 一覧）を ssh に読ませない
	agents=$(herdr --machine "$id" agent list </dev/null 2>/dev/null) || return 0
	workspaces=$(herdr --machine "$id" workspace list </dev/null 2>/dev/null) || return 0

	local pane status focused workspace task seen on_click
	while IFS=$sep read -r pane status focused workspace task; do
		seen=false
		[[ $selected == true && $focused == true ]] && seen=true
		printf -v on_click '%q --machine %q agent focus %q' "$herdr_bin" "$id" "$pane"
		# 初回は今の状態を覚えるだけにする（起動のたびに idle の agent が全部通知されるのを防ぐ）
		agent_notify "$id:$pane" "$status" "$seen" "$label / $workspace" "$task" "$on_click" quiet
	done < <(jq -r --arg s "$sep" --argjson ws "$workspaces" '
		($ws.result.workspaces | map({(.workspace_id): .label}) | add // {}) as $labels
		| .result.agents[]
		| [.pane_id, .agent_status, .focused, ($labels[.workspace_id] // ""),
		   (.terminal_title_stripped // .agent // "agent")]
		| join($s)' <<<"$agents")
}

main "$@"
