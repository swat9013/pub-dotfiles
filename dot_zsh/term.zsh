# 端末に取り残された private mode を解除するユーティリティ。
#
# SSH の異常切断時、リモート multiplexer (mouse on 等) がローカル端末に有効化した
# マウス報告モード等を解除するシーケンスが届かず残留する。結果、ローカル prompt で
# マウス操作が `\e[<65;171;9M` のような SGR(1006) イベントとして生入力され、
# 行編集が壊れる。これを解除して復旧する。reset(1) と違い RIS を送らないため
# scrollback は温存する。

# マウス報告 (1000/1002/1003/1006) / 代替画面 (1049) / bracketed paste (2004) を解除。
# hd の @host 経路 (hd.zsh) からも復帰時クリーンアップとして呼ばれる。
_term_reset_modes() {
  printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l\033[?1049l\033[?2004l'
}

# 対話復旧用: private mode 解除 + termios 正常化。
# 切断後にゴミ入力で固まったとき、ブラインドで `fixterm` + Enter を打てば復旧する。
fixterm() {
  _term_reset_modes
  stty sane
}
