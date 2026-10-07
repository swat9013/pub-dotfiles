# mise: activate 意味論を維持したまま prompt-ready latency から外す (#120)。
#
# activate script の末尾は `mise hook-env` を同期実行する (実測 ~120-155ms)。これは
# 「今の cwd に対する tool version の解決」そのもので cache できない work なので、
# 消すのではなく prompt 表示後へ回す。shims 移行 (`command -v node` の出力が shim path に
# 変わる非対称な変更) は却下し、defer で踏んだ race の fallback としてのみ残す。
#
# activate 出力は cache しない。mise 2026.9.4 の `mise activate zsh` は呼び出した shell の
# PATH を絶対値で焼いた `export PATH='...'` を出力するため、file に凍結すると生成時の PATH が
# 後続の全 shell で再生され、.zshrc 末尾の path-layout が足した ~/.local/bin 等を黙って消す。
# 毎回生成すれば snapshot は評価する shell 自身のものになり構造的に正しい。生成コストは
# 実測 0.00s で、元から defer 後の work なので cache の利得は無かった。
#
# 生成を関数に包むのは、`startup_defer eval "$(mise activate zsh)"` だと command substitution
# が .zshrc の読み込み時点 — path-layout より前 — で展開され、凍結と同じ PATH を焼いてしまう
# ため。関数越しなら substitution も defer 後に走る。
_mise_activate() {
    eval "$(mise activate zsh)"
}
command -v mise >/dev/null 2>&1 && startup_defer _mise_activate
