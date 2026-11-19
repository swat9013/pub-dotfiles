#!/usr/bin/env bash
# herdr plugin の event hook: pane / tab / workspace を切り替えて見に行った pane の
# 通知を取り下げる。通知は対応が要る間だけ残す。
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pane=$(jq -r '.focused_pane_id // empty' <<<"${HERDR_PLUGIN_CONTEXT_JSON:-null}")
[[ -n $pane ]] || exit 0
# CLI からの focus（他の script など）では、人が見たとは限らない
ghostty_is_frontmost || exit 0
agent_notify_dismiss "local:$pane"
