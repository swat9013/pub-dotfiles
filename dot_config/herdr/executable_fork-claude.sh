#!/usr/bin/env bash
# herdr shell: フォーカス中 pane の Claude Code session を fork し、右 pane で開く（Ghostty cmd+shift+f → prefix+shift+f）。
# 元 session は止めずに、同じ文脈で質問・深掘りするための入口。
#
# session ID は herdr の claude integration が pane に報告した agent_session から取る
# （keybind 起動の script は Claude の外で動くため CLAUDE_SESSION_ID は使えない）。
# fork 側は `--fork-session` で新 session ID になり、元の transcript には書き込まない。
# Claude の無い pane で押した場合は通知だけ出して何もしない。
#
# テスト用の env var 契約:
#   HERDR_FORK_CLAUDE_DRY_RUN=1 … split せず実行予定コマンドを 1 行 print
set -euo pipefail

# herdr server の素 PATH 対策 (brew / ~/.local/bin 補完)。--remote 経路で必須
. "$(dirname "${BASH_SOURCE[0]}")/path-bootstrap.sh"

main() {
	local info
	info=$(herdr pane current)

	local session_id
	session_id=$(printf '%s' "$info" | jq -r '
		.result.pane.agent_session
		| select(.agent == "claude" and .kind == "id")
		| .value // empty')
	# 送る文字列にそのまま埋め込むため、UUID 形の文字だけを受け付ける
	if [[ -z "$session_id" || ! "$session_id" =~ ^[0-9A-Za-z-]+$ ]]; then
		herdr notification show "fork-claude" --body "この pane に Claude session がありません" >/dev/null
		exit 0
	fi

	local pane_id cwd title
	pane_id=$(printf '%s' "$info" | jq -r '.result.pane.pane_id')
	cwd=$(printf '%s' "$info" | jq -r '.result.pane.cwd')
	title=$(printf '%s' "$info" | jq -r '.result.pane.terminal_title_stripped // ""')
	# タイトル未生成の session は "Claude Code" が返る。その場合は ID 先頭 8 桁で見分ける
	if [[ -z "$title" || "$title" == "Claude Code" ]]; then
		title="${session_id:0:8}"
	fi

	# 表示名は pane の env で渡し、送る文字列には変数参照だけを書く。
	# タイトルの空白・引用符・$ を shell の quote 規則に乗せずに済ませるため
	local name="fork: $title"
	local cmd="claude --resume $session_id --fork-session -n \"\$HERDR_FORK_NAME\" --effort low"

	if [[ "${HERDR_FORK_CLAUDE_DRY_RUN:-}" == "1" ]]; then
		printf 'cd %s && HERDR_FORK_NAME=%s %s\n' "$cwd" "$name" "$cmd"
		exit 0
	fi

	local new_pane
	new_pane=$(herdr pane split --pane "$pane_id" --direction right --cwd "$cwd" \
		--env "HERDR_FORK_NAME=$name" --focus | jq -r '.result.pane.pane_id')
	herdr pane run "$new_pane" "$cmd" >/dev/null
}

main "$@"
