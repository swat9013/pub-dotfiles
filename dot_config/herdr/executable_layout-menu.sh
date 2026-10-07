#!/usr/bin/env bash
# herdr popup: レイアウト選択メニュー。
# Ghostty cmd+i → `\x11i` → `prefix+i` で起動される。
# 番号キー 1..5 で即決、fzf incremental search も併用可。
#
# 起動元 pane を popup 環境 (HERDR_ACTIVE_PANE_ID / HERDR_ACTIVE_PANE_CWD) から拾い、
# `layouts/<name>.sh` に env として引き渡して委譲する (layouts 側は env が無ければ
# `herdr pane current` にフォールバックするので、直接 keybind 起動 (prefix+shift+l/e) とも共存する)。
#
# 3 variant (incremental / 数字即決 / +pane 操作) を比較して数字即決を採った。
# 1 (grid) と 2 (even) は「既存 pane の整地」、3..5 は「pane を生成する layout」。
# 最頻の grid を先頭に置くため、追加時に既存項目の番号を 1 つずつ繰り下げた。
# pane 操作 (kill / swap) の同居はメニューが散らかるため入れていない。

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/path-bootstrap.sh"

selected=$(fzf --reverse --height=100% --prompt='layout> ' --no-info \
	--bind='1:pos(1)+accept' \
	--bind='2:pos(2)+accept' \
	--bind='3:pos(3)+accept' \
	--bind='4:pos(4)+accept' \
	--bind='5:pos(5)+accept' <<'EOF'
1 grid
2 even
3 ide
4 4col-lazygit
5 emacs-dev
EOF
) || exit 0

layout=$(printf '%s' "$selected" | awk '{print $2}')
exec "$(dirname "${BASH_SOURCE[0]}")/layouts/${layout}.sh"
