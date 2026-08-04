# mise: activate 意味論を維持したまま prompt-ready latency から外す (#120)。
#
# activate script の末尾は `mise hook-env` を同期実行する (実測 ~120-155ms)。これは
# 「今の cwd に対する tool version の解決」そのもので cache できない work なので、
# 消すのではなく prompt 表示後へ回す。shims 移行 (`command -v node` の出力が shim path に
# 変わる非対称な変更) は却下し、defer で踏んだ race の fallback としてのみ残す。
#
# activate script 本体の生成は共有 primitive で cache する
# (旧実装は cache の存在だけを見ており、mise 更新時の手動削除を前提にしていた)。
command -v mise >/dev/null 2>&1 && startup_defer cache_eval mise mise activate zsh
