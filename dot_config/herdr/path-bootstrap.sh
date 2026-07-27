# herdr popup / layout script 用の PATH 自己補完 (source して使う)。
#
# herdr server は login shell を経ずに起動されることがあり（特に `herdr --remote` の
# ssh 非対話経路では PATH が /usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin の素の値）、
# [[keys.command]] から実行される script が brew 配下のコマンドや ~/.local/bin の
# herdr 本体を見つけられず即死する。存在する candidate だけを冪等に prepend して補う。
#
# 正本 ~/.config/shell/path-prepend.sh を source し herdr 用 dir list を適用する thin adapter。
# 参照は BASH_SOURCE 相対 (../shell/) — XDG 未設定や apply 前の worktree/CI でも解決するため。
. "$(dirname "${BASH_SOURCE[0]}")/../shell/path-prepend.sh"
# 後に書いた dir ほど先頭に来る。herdr 本体が入る ~/.local/bin を最優先にする。
path_prepend \
	/home/linuxbrew/.linuxbrew/bin \
	"$HOME/.linuxbrew/bin" \
	/opt/homebrew/bin \
	"$HOME/.local/bin"
export PATH
