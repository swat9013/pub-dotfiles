# path-layout.sh (→ ~/.config/shell/path-layout.sh): この環境の PATH 順序の正本。
# path_prepend の primitive を source し、確定順を適用するのみ。
#
# .zshrc (対話 shell) と .zlogin (login shell) の双方がこれを読む。順序の定義を
# 1 箇所に閉じ込め、片方だけ直して順序が食い違う事故を構造で防ぐ。
# 後に書いた dir ほど先頭 = 最終順位 .local/bin > go/bin > homebrew > /usr/local/sbin。
# Darwin gate は path_prepend 側の -d guard に委ねて置かない。
. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/path-prepend.sh"
path_prepend /usr/local/sbin /opt/homebrew/sbin /opt/homebrew/bin "$HOME/go/bin" "$HOME/.local/bin"
