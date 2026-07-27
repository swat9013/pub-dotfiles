#!/bin/bash
# emacs + 右 2 列 + 下段 shell レイアウト (herdr 版)
# 現在の invoking pane を左上として構築する。他 pane は温存 (並び替え相当)。
#
# ┌──────────┬─────┬─────┐
# │          │     │     │
# │  emacs   │ sh  │ sh  │   上 (高さ 3/4)
# │          │     │     │
# ├──────────┴─────┴─────┤
# │        shell         │   下 (高さ 1/4)
# └──────────────────────┘

set -euo pipefail

# herdr server の素 PATH 対策 (brew / ~/.local/bin 補完)。--remote 経路で必須
. "$(dirname "${BASH_SOURCE[0]}")/../path-bootstrap.sh"

# popup 起動 (layout-menu.sh 経由) では env から起動元 pane を継承する。
# 直接 keybind 起動 (prefix+shift+e) では env 未設定なので herdr pane current にフォールバック。
if [[ -n "${HERDR_ACTIVE_PANE_ID:-}" && -n "${HERDR_ACTIVE_PANE_CWD:-}" ]]; then
	pane="$HERDR_ACTIVE_PANE_ID"
	cwd="$HERDR_ACTIVE_PANE_CWD"
else
	info=$(herdr pane current)
	pane=$(printf '%s' "$info" | jq -r '.result.pane.pane_id')
	cwd=$(printf '%s' "$info" | jq -r '.result.pane.cwd')
fi

# 下段 1/4 (ratio は「新規 pane の割合」を想定)
herdr pane split --pane "$pane" --direction down  --ratio 0.25 --cwd "$cwd" --no-focus >/dev/null

# 上段の左右分割 x 2 (右 2 列)
herdr pane split --pane "$pane" --direction right --cwd "$cwd" --no-focus >/dev/null
herdr pane split --pane "$pane" --direction right --cwd "$cwd" --no-focus >/dev/null

herdr pane run "$pane" "emacs -nw"
