#!/usr/bin/env bash
# Emacs 設定の byte-compile 成果物 (.elc) を配布先から消す。
# 設定の .elc は配布しない。以前の run_onchange_byte-compile-emacs.sh が作った
# .elc が残っていると、Emacs は更新後の .el ではなく古い .elc を読み続ける。
# straight が管理する package の .elc (straight/build/) には触れない。
set -euo pipefail

EMACS_DIR="$HOME/.emacs.d"
rm -f "$EMACS_DIR/init.elc" "$EMACS_DIR/early-init.elc" "$EMACS_DIR"/lisp/*.elc
