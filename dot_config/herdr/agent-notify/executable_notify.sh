#!/usr/bin/env bash
# herdr plugin の event hook: 手元の server の agent が done / idle / blocked になったら
# macOS 通知を出す。通知を押すと Ghostty を前面に出し、その agent の pane へ移動する。
#
# herdr 標準の通知（[ui.toast]）は文面が「<agent> finished / <workspace>」固定で、
# 押しても terminal を前面に出すだけなので、こちらで出す。
# 通知する条件は lib.sh の agent_notify にある。
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

herdr_bin=${HERDR_BIN_PATH:-herdr}

main() {
	local status pane
	status=$(jq -r '.data.agent_status // empty' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")
	pane=$(jq -r '.data.pane_id // empty' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")
	[[ -n $pane ]] || return 0

	local agent workspace task on_click
	agent=$("$herdr_bin" agent get "$pane" | jq -c '.result.agent')
	workspace=$(jq -r '.workspace_label // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}")
	task=$(jq -r '.terminal_title_stripped // .agent // "agent"' <<<"$agent")
	printf -v on_click 'HERDR_SOCKET_PATH=%q %q agent focus %q' \
		"${HERDR_SOCKET_PATH:-}" "$herdr_bin" "$pane"

	agent_notify "local:$pane" "$status" "$(jq -r '.focused' <<<"$agent")" \
		"$workspace" "$task" "$on_click"
}

main "$@"
