#!/usr/bin/env bash
# herdr popup: 起動元 pane の repo の open な issue / CL を fzf で選び、URL を pane へ send-text する。
#   issue … prefix+shift+i（Ghostty cmd+shift+i → \x11I）
#   cl    … prefix+shift+c（Ghostty cmd+shift+c → \x11C）。CL は GitHub PR / GitLab MR の総称
#
# 取得元は origin の host で選ぶ: github.com → gh / gitlab を含む host → glab（sbx-repo.sh と同じ規則）。
# 一覧を出せないとき（repo 外・対応外の host・未認証など）は herdr の通知で理由を出して閉じる。
# 起動元 pane は HERDR_ACTIVE_PANE_ID / HERDR_ACTIVE_PANE_CWD で受け取る（file-picker.sh と同型）。
#
# テスト用の env var 契約:
#   HERDR_ISSUE_CL_PICKER_SOURCE_ONLY=1 … main を実行せず関数定義だけを読み込む
#   HERDR_ISSUE_CL_PICKER_DRY_RUN=1     … 一覧取得の前で止め、実行予定の list コマンドを 1 行 print。
#                                        通知は herdr に出さず "notify: <本文>" を print
set -euo pipefail

# herdr server の素 PATH 対策 (brew / ~/.local/bin 補完)。--remote 経路で必須
. "$(dirname "${BASH_SOURCE[0]}")/path-bootstrap.sh"

LIMIT=100

notify() {
	if [[ "${HERDR_ISSUE_CL_PICKER_DRY_RUN:-}" == "1" ]]; then
		printf 'notify: %s\n' "$1"
		return
	fi
	herdr notification show "issue-cl-picker" --body "$1" >/dev/null 2>&1 || echo "$1" >&2
}

# origin URL から使う CLI を返す（対応外なら空）
forge_for_origin() {
	case "$1" in
	*github.com*) echo gh ;;
	*gitlab*) echo glab ;;
	*) echo "" ;;
	esac
}

# origin URL（https / ssh / scp 形式）を gh / glab の -R が受ける https URL へ揃える
normalize_origin() {
	local url="$1" scheme=""
	[[ "$url" == *://* ]] && scheme="${url%%://*}"
	url="${url#*://}"
	url="${url#*@}"
	if [[ -z "$scheme" && "$url" =~ ^([^/:]+):(.+)$ ]]; then
		# scp 形式 host:path の区切りを / にする
		url="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
	elif [[ "$scheme" == "ssh" && "$url" =~ ^([^/:]+):[0-9]+/(.+)$ ]]; then
		# ssh の port は https URL では意味を持たないので落とす
		url="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
	fi
	url="${url%/}"
	printf 'https://%s' "${url%.git}"
}

# list コマンドの JSON（stdin）を fzf の行「番号<TAB>URL<TAB>表示」へ整形する
# $1: gh | glab / $2: issue | cl
to_rows() {
	local forge="$1" kind="$2" sign="#"
	[[ "$forge" == "glab" && "$kind" == "cl" ]] && sign="!"
	if [[ "$forge" == "gh" ]]; then
		jq -r --arg s "$sign" '.[] | [.number, .url,
			"\($s)\(.number) \(if .isDraft then "[draft] " else "" end)\(.title)"] | @tsv'
	else
		jq -r --arg s "$sign" '.[] | [.iid, .web_url,
			"\($s)\(.iid) \(if .draft then "[draft] " else "" end)\(.title)"] | @tsv'
	fi
}

# fzf の選択行群（stdin）から URL を空白区切り 1 行にする。
# 末尾スペースは意図的（send-text でカーソルを次入力位置へ送る）
join_urls() {
	local url out=""
	while IFS=$'\t' read -r _ url _; do
		[[ -n "$url" ]] && out+="$url "
	done
	printf '%s' "$out"
}

main() {
	local kind="${1-}"
	if [[ "$kind" != "issue" && "$kind" != "cl" ]]; then
		echo "Usage: $(basename "$0") issue|cl" >&2
		exit 1
	fi
	if [[ -z "${HERDR_ACTIVE_PANE_ID-}" ]]; then
		echo "Error: herdr popup 内で実行してください (HERDR_ACTIVE_PANE_ID 未設定)。" >&2
		exit 1
	fi
	local pane_id="$HERDR_ACTIVE_PANE_ID"
	local pane_dir="${HERDR_ACTIVE_PANE_CWD:-$PWD}"

	local origin
	if ! origin=$(git -C "$pane_dir" remote get-url origin 2>/dev/null); then
		notify "origin のある git repo ではありません: $pane_dir"
		exit 0
	fi
	local forge
	forge=$(forge_for_origin "$origin")
	if [[ -z "$forge" ]]; then
		notify "GitHub / GitLab の repo ではありません: $origin"
		exit 0
	fi
	local repo
	repo=$(normalize_origin "$origin")

	local -a list_cmd
	local sub="issue"
	if [[ "$kind" == "cl" && "$forge" == "gh" ]]; then
		sub="pr"
	elif [[ "$kind" == "cl" ]]; then
		sub="mr"
	fi
	if [[ "$forge" == "gh" ]]; then
		local fields="number,title,url"
		[[ "$kind" == "cl" ]] && fields+=",isDraft"
		list_cmd=(gh "$sub" list -R "$repo" --state open --limit "$LIMIT" --json "$fields")
	else
		list_cmd=(glab "$sub" list -R "$repo" --per-page "$LIMIT" --output json)
	fi

	if [[ "${HERDR_ISSUE_CL_PICKER_DRY_RUN:-}" == "1" ]]; then
		printf '%s\n' "${list_cmd[*]}"
		exit 0
	fi
	if ! command -v "$forge" >/dev/null 2>&1; then
		notify "'$forge' が見つかりません"
		exit 0
	fi

	echo "読み込み中: $repo" >&2
	local json err
	err=$(mktemp)
	if ! json=$("${list_cmd[@]}" 2>"$err"); then
		notify "$forge $sub list に失敗: $(head -n 1 "$err")"
		rm -f "$err"
		exit 0
	fi
	rm -f "$err"

	local rows
	rows=$(printf '%s' "$json" | to_rows "$forge" "$kind")
	if [[ -z "$rows" ]]; then
		notify "open な $kind がありません: $repo"
		exit 0
	fi

	local preview_cmd
	preview_cmd="$(printf '%q ' "$forge" "$sub" view -R "$repo"){1}"

	local selected
	selected=$(printf '%s\n' "$rows" | fzf --multi --reverse \
		--delimiter $'\t' --with-nth 3 \
		--preview "$preview_cmd" --preview-window 'right:60%:wrap' || true)
	[[ -z "$selected" ]] && exit 0

	herdr pane send-text "$pane_id" "$(printf '%s\n' "$selected" | join_urls)"
}

if [[ "${HERDR_ISSUE_CL_PICKER_SOURCE_ONLY:-}" != "1" ]]; then
	main "$@"
fi
