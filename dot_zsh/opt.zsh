#
# history
#

# History file location and size
export HISTFILE=$HOME/.zsh-history
export HISTSIZE=100000
export SAVEHIST=100000

# 共有する
setopt share_history

# 重複を記録しない
setopt hist_ignore_dups

# ヒストリに追加されるコマンド行が古いものと同じなら古いものを削除
setopt hist_ignore_all_dups

# スペースで始まるコマンド行はヒストリリストから削除
setopt hist_ignore_space

# 余分な空白は詰めて記録
setopt hist_reduce_blanks

# 古いコマンドと同じものは無視
setopt hist_save_no_dups

# historyコマンドは履歴に登録しない
setopt hist_no_store

# 履歴をインクリメンタルに追加
setopt inc_append_history
