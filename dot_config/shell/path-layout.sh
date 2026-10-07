# path-layout.sh (→ ~/.config/shell/path-layout.sh): この環境の PATH 順序の正本。
# path_prepend の primitive を source し、確定順を適用するのみ。
#
# .zshrc (対話 shell) と .zlogin (login shell) の双方がこれを読む。順序の定義を
# 1 箇所に閉じ込め、片方だけ直して順序が食い違う事故を構造で防ぐ。
# 後に書いた dir ほど先頭 = 最終順位 .local/bin > go/bin > homebrew > /usr/local/sbin > mise shims。
# Darwin gate は path_prepend 側の -d guard に委ねて置かない。
#
# mise shims を最下位で足すのは、mise activate が prompt 表示後へ defer されている
# (dot_zsh/mise.zsh) 一方で、starship / sheldon / fzf / herdr のように **起動中に解決が要る**
# CLI が mise 管理へ移った (ADR 0016) ため。activate 前の window では install path が
# PATH に無く、cache_eval が binary を解決できずに init を丸ごと skip する
# (cache file が有効でも `_cache_eval_resolve` の失敗で return する)。shims は静的な dir
# なので fork 無しでこの穴だけを塞げる。最下位に置くのは、activate 後は install path が
# 先頭に来て `command -v` の出力が従来どおり実 path に戻るようにするため。
. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/path-prepend.sh"
path_prepend "$HOME/.local/share/mise/shims" /usr/local/sbin /opt/homebrew/sbin /opt/homebrew/bin "$HOME/go/bin" "$HOME/.local/bin"
