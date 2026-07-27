#!/bin/bash
# IDE レイアウト (herdr 版)
# 引数なし: 右分割 + 左を上下分割（3 pane）
# 引数 1  : 右分割のみ（2 pane）
# 他 pane は温存（並び替え相当）。

set -euo pipefail

# herdr server の素 PATH 対策 (brew / ~/.local/bin 補完)。--remote 経路で必須
. "$(dirname "${BASH_SOURCE[0]}")/../path-bootstrap.sh"

# popup 起動 (layout-menu.sh 経由) では env から起動元 pane を継承する。
# 直接 keybind 起動では env 未設定なので herdr pane current にフォールバック。
if [[ -n "${HERDR_ACTIVE_PANE_ID:-}" && -n "${HERDR_ACTIVE_PANE_CWD:-}" ]]; then
	pane="$HERDR_ACTIVE_PANE_ID"
	cwd="$HERDR_ACTIVE_PANE_CWD"
else
	info=$(herdr pane current)
	pane=$(printf '%s' "$info" | jq -r '.result.pane.pane_id')
	cwd=$(printf '%s' "$info" | jq -r '.result.pane.cwd')
fi

case "${1:-}" in
  "")
    herdr pane split --pane "$pane" --direction right --cwd "$cwd" --no-focus >/dev/null
    herdr pane split --pane "$pane" --direction down  --cwd "$cwd" --no-focus >/dev/null
    ;;
  1)
    herdr pane split --pane "$pane" --direction right --cwd "$cwd" --no-focus >/dev/null
    ;;
  *)
    echo "[ERROR] $1 は設定されていない引数です。" >&2
    exit 1
    ;;
esac
