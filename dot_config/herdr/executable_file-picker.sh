#!/usr/bin/env bash
# herdr popup ファイルピッカー
# prefix C-f の [[keys.command]] popup から起動され、fd|fzf で選んだファイルパスを
# 起動元 pane のカーソル位置へ send-text する。pane 内で claude/codex/gemini
# を検知した場合は @file 記法で、それ以外は %q escape して挿入する。
#
# 起動元 pane は HERDR_ACTIVE_PANE_ID / HERDR_ACTIVE_PANE_CWD で受け取る。
# herdr は popup 環境に HERDR_ACTIVE_PANE_ID / HERDR_ACTIVE_PANE_CWD を渡す。
set -euo pipefail

# herdr server の素 PATH 対策 (brew / ~/.local/bin 補完)。--remote 経路で必須
. "$(dirname "${BASH_SOURCE[0]}")/path-bootstrap.sh"

# 選択パス群を pane へ送る一行文字列に整形する純粋関数。
# $1: at_prefix_mode ("true" なら @ 付与) / $2..: パス（1 件以上必須、呼び出し側が保証）
format_paths() {
	local mode="$1"
	shift
	local out
	if [[ "$mode" == "true" ]]; then
		printf -v out "@%s " "$@"
	else
		local escaped=() path esc
		for path in "$@"; do
			printf -v esc "%q" "$path"
			escaped+=("$esc")
		done
		out=$(printf "%s " "${escaped[@]}")
	fi
	# 末尾スペースは意図的（send-text でカーソルを次入力位置へ送る）
	printf '%s' "$out"
}

main() {
	if [[ -z "${HERDR_ACTIVE_PANE_ID-}" ]]; then
		echo "Error: herdr popup 内で実行してください (HERDR_ACTIVE_PANE_ID 未設定)。" >&2
		exit 1
	fi

	if ! command -v fd >/dev/null 2>&1; then
		echo "Error: 'fd' が見つかりません。" >&2
		exit 1
	fi

	local pane_id="$HERDR_ACTIVE_PANE_ID"
	local pane_dir="${HERDR_ACTIVE_PANE_CWD:-$PWD}"

	local preview_cmd
	if command -v bat >/dev/null 2>&1; then
		preview_cmd="bat --style=numbers --color=always {}"
	else
		preview_cmd="cat {}"
	fi

	# cd してから fd することで pane cwd 相対の綺麗なパスを得る
	local selected
	selected=$(
		cd "$pane_dir" || exit 1
		fd -H --follow --type f --exclude .git \
			| fzf --multi --reverse --preview "$preview_cmd" || true
	)
	[[ -z "$selected" ]] && exit 0

	# pane で AI アシスタントが動いていれば @file 記法にする。
	# herdr の process-info 出力（agent 検出込み）を寛容に grep する。
	local at_prefix_mode=false
	if herdr pane process-info --pane "$pane_id" 2>/dev/null \
		| grep -qiE 'claude|codex|gemini'; then
		at_prefix_mode=true
	fi

	local files=() line
	while IFS= read -r line; do
		[[ -n "$line" ]] && files+=("$line")
	done <<<"$selected"

	local oneline
	oneline=$(format_paths "$at_prefix_mode" "${files[@]}")
	herdr pane send-text "$pane_id" "$oneline"
}

if [[ "${FILE_PICKER_SOURCE_ONLY:-}" != "1" ]]; then
	main "$@"
fi
