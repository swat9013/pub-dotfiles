# shellcheck shell=bash
# agent-notify の共通処理 (source して使う)。状態の変化 1 件を受け、通知するか決めて出す。
#
# テスト用の env var 契約:
#   HERDR_AGENT_NOTIFY_DRY_RUN=1 … 通知も取り下げもせず terminal-notifier の引数を 1 行ずつ print
#   HERDR_AGENT_NOTIFY_STATE_DIR … 直前の状態の置き場を差し替える

# herdr server / Hammerspoon の素 PATH 対策 (brew 補完)
. "$(dirname "${BASH_SOURCE[0]}")/../path-bootstrap.sh"

agent_notify_state_dir=${HERDR_AGENT_NOTIFY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-agent-notify}

# agent_notify KEY STATUS SEEN PLACE TASK ON_CLICK FIRST
#   KEY      … agent を一意に指す文字列（直前の状態の file 名と通知の group になる）
#   STATUS   … 今の状態（done / idle / blocked のときだけ通知する）
#   SEEN     … "true" なら herdr 上で表示中の pane。Ghostty が最前面なら通知しない
#   PLACE    … 通知の title に出す居場所（workspace 名など）。色の印もここから決まる
#   TASK     … 通知の本文（タスク名）
#   ON_CLICK … 通知を押したときに走らせる shell command
#   FIRST    … 直前の状態が無いときの扱い。"quiet" なら記録だけして通知しない
agent_notify() {
	local key=${1//[^A-Za-z0-9]/_} status=$2 seen=$3 place=$4 task=$5 on_click=$6 first=${7:-}

	# 直前の状態を agent ごとに残す（herdr は直前の状態を教えない）
	local state_file="$agent_notify_state_dir/$key" prev=""
	mkdir -p "$agent_notify_state_dir"
	if [[ -f $state_file ]]; then
		prev=$(<"$state_file")
	elif [[ $first == quiet ]]; then
		printf '%s' "$status" >"$state_file"
		return 0
	fi
	[[ $prev == "$status" ]] || printf '%s' "$status" >"$state_file"

	# 通知は対応が要る間だけ残す。表示中の pane は見えているので、出さず、出ていれば取り下げる
	if [[ $seen == true ]] && ghostty_is_frontmost; then
		agent_notify_dismiss "$key"
		return 0
	fi
	[[ $prev != "$status" ]] || return 0

	# done は既定の状態なので文字にしない。入力待ちだけ subtitle で区別する
	local subtitle=""
	case $status in
		done) ;;
		# done の pane を見に行くと idle になる。見たので、同じ完了の通知は取り下げる
		idle) [[ $prev != "done" ]] || { agent_notify_dismiss "$key"; return 0; } ;;
		blocked) subtitle="✋ 入力待ち" ;;
		# 動き出した agent に対応は要らない
		*) agent_notify_dismiss "$key"; return 0 ;;
	esac

	# 居場所ごとに決まった色の印を付け、どの project の通知かを色で見分ける
	local -a marks=(🔴 🟠 🟡 🟢 🔵 🟣 🟤 🟥 🟧 🟨 🟩 🟦 🟪 🟫)
	local sum
	sum=$(cksum <<<"$place")
	local -a args=(
		-title "${marks[${sum%% *} % ${#marks[@]}]} ${place}"
		-message "$task"
		-group "herdr-agent-${key}"
		-execute "${on_click}; open -b com.mitchellh.ghostty"
	)
	[[ -z $subtitle ]] || args+=(-subtitle "$subtitle")
	if [[ -n ${HERDR_AGENT_NOTIFY_DRY_RUN:-} ]]; then
		printf '%s\n' "${args[@]}"
		return 0
	fi
	terminal-notifier "${args[@]}" >/dev/null
}

# agent_notify_dismiss KEY … その agent の通知が出ていれば取り下げる
agent_notify_dismiss() {
	local group="herdr-agent-${1//[^A-Za-z0-9]/_}"
	if [[ -n ${HERDR_AGENT_NOTIFY_DRY_RUN:-} ]]; then
		printf '%s\n' -remove "$group"
		return 0
	fi
	terminal-notifier -remove "$group" >/dev/null
}

ghostty_is_frontmost() {
	lsappinfo info -only bundleid "$(lsappinfo front)" | grep -q 'com\.mitchellh\.ghostty'
}
