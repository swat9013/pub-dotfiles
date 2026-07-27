#!/bin/bash
# 4 列 + 左縦分割 + lazygit レイアウト (herdr 版)
# 現在の invoking pane を左上とし、右方向に 3 回 split (4 列) + 左端を上下 split。
# 他 pane はそのまま残す（並び替え相当）。fresh な pane から呼ぶことを想定。
#
# ┌──────────┬──────────┬──────────┬──────────┐
# │ lazygit  │          │          │          │
# ├──────────┤  shell   │  shell   │  shell   │
# │  shell   │          │          │          │
# └──────────┴──────────┴──────────┴──────────┘

set -euo pipefail

# herdr server の素 PATH 対策 (brew / ~/.local/bin 補完)。--remote 経路で必須
. "$(dirname "${BASH_SOURCE[0]}")/../path-bootstrap.sh"

# popup 起動 (layout-menu.sh 経由) では env から起動元 pane を継承する。
# 直接 keybind 起動 (prefix+shift+l) では env 未設定なので herdr pane current にフォールバック。
if [[ -n "${HERDR_ACTIVE_PANE_ID:-}" && -n "${HERDR_ACTIVE_PANE_CWD:-}" ]]; then
	pane="$HERDR_ACTIVE_PANE_ID"
	cwd="$HERDR_ACTIVE_PANE_CWD"
else
	info=$(herdr pane current)
	pane=$(printf '%s' "$info" | jq -r '.result.pane.pane_id')
	cwd=$(printf '%s' "$info" | jq -r '.result.pane.cwd')
fi

herdr pane split --pane "$pane" --direction right --cwd "$cwd" --no-focus >/dev/null
herdr pane split --pane "$pane" --direction right --cwd "$cwd" --no-focus >/dev/null
herdr pane split --pane "$pane" --direction right --cwd "$cwd" --no-focus >/dev/null
herdr pane split --pane "$pane" --direction down  --cwd "$cwd" --no-focus >/dev/null

herdr pane run "$pane" "lazygit"
