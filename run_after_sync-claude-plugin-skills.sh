#!/bin/sh
# Claude Code plugin の skill・agent を opencode / pi / Antigravity から読む symlink・変換 file を張り直す。
# plugin の更新は chezmoi の source に現れないので run_onchange_ では契機を表せない。
# 張り直しは一時 dir で組み立てて入れ替えるだけで、何度走っても結果は同じになる。
# after にしているのは、同じ apply で配布した最新の script を使うため。
set -e
script="${HOME}/.local/bin/sync-claude-plugin-skills"
[ -x "$script" ] || exit 0
# best-effort。plugin 側の不整合で apply 全体を失敗させない
"$script" || echo "warn: sync-claude-plugin-skills に失敗した" >&2
