#!/usr/bin/env bash
# herdr popup: 実行元 pane の repo ルートで emacs -nw を起動する（Ghostty cmd+e → prefix+ctrl+e）。
# クリップボードに repo 内ファイルのパスがあればそのファイルを開く（path:line 形式は行ジャンプ）。
# herdr は popup 環境に HERDR_ACTIVE_PANE_CWD を渡す（file-picker.sh と同型）。
#
# 無効入力（空・複数行・repo 外・不存在）はすべて repo ルートでの素起動に静かにフォールバックし、
# popup がエラーで即閉じする事態を避ける。
#
# テスト用の env var 契約:
#   HERDR_EMACS_POPUP_DRY_RUN=1 … exec せず実行予定コマンドを 1 行 print
#   HERDR_EMACS_POPUP_CLIP      … 設定時（空文字含む）は pbpaste の代わりにこの値を使う
set -euo pipefail

# herdr server の素 PATH 対策 (brew / ~/.local/bin 補完)。--remote 経路で必須
. "$(dirname "${BASH_SOURCE[0]}")/path-bootstrap.sh"

read_clipboard() {
	if [[ -n "${HERDR_EMACS_POPUP_CLIP+x}" ]]; then
		printf '%s' "$HERDR_EMACS_POPUP_CLIP"
	else
		pbpaste 2>/dev/null || true
	fi
}

main() {
	local pane_dir="${HERDR_ACTIVE_PANE_CWD:-$PWD}"
	local repo_root
	repo_root=$(git -C "$pane_dir" rev-parse --show-toplevel 2>/dev/null) || repo_root="$pane_dir"
	[[ -d "$repo_root" ]] || repo_root="$HOME"

	# クリップボードを trim。複数行は無効扱い（フォールバック）
	local clip
	clip=$(read_clipboard)
	clip="${clip#"${clip%%[![:space:]]*}"}"
	clip="${clip%"${clip##*[![:space:]]}"}"
	[[ "$clip" == *$'\n'* ]] && clip=""

	# 末尾の :LINE または :LINE:COL を行番号として分離（fzf-grep-copy の path:line 形式 / rg --column 形式対応）
	# emacs -nw の起動引数で列指定は不要なので COL は破棄する
	local line=""
	if [[ "$clip" =~ ^(.+):([0-9]+):[0-9]+$ ]]; then
		clip="${BASH_REMATCH[1]}"
		line="${BASH_REMATCH[2]}"
	elif [[ "$clip" =~ ^(.+):([0-9]+)$ ]]; then
		clip="${BASH_REMATCH[1]}"
		line="${BASH_REMATCH[2]}"
	fi

	# パス解決: 絶対パスはそのまま、相対パスは repo ルート基準 → pane cwd 基準の順
	local candidate=""
	if [[ -n "$clip" ]]; then
		if [[ "$clip" == /* ]]; then
			candidate="$clip"
		elif [[ -f "$repo_root/$clip" ]]; then
			candidate="$repo_root/$clip"
		elif [[ -f "$pane_dir/$clip" ]]; then
			candidate="$pane_dir/$clip"
		fi
	fi

	# 検証: 通常ファイルであり、realpath が repo ルート配下にあること
	local target=""
	if [[ -n "$candidate" && -f "$candidate" ]]; then
		local real root_real
		real=$(realpath "$candidate" 2>/dev/null) || real=""
		root_real=$(realpath "$repo_root" 2>/dev/null) || root_real="$repo_root"
		if [[ -n "$real" && ( "$real" == "$root_real" || "$real" == "$root_real"/* ) ]]; then
			target="$real"
		fi
	fi

	local -a cmd=(emacs -nw)
	if [[ -n "$target" ]]; then
		[[ -n "$line" ]] && cmd+=("+$line")
		cmd+=("$target")
	fi

	if [[ "${HERDR_EMACS_POPUP_DRY_RUN:-}" == "1" ]]; then
		printf 'cd %s && %s\n' "$repo_root" "${cmd[*]}"
		exit 0
	fi

	cd "$repo_root"
	exec "${cmd[@]}"
}

main "$@"
