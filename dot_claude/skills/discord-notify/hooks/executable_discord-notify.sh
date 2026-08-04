#!/bin/bash
# Claude Code の hook から呼ばれ、Discord webhook へ通知を送る。
#
#   permission   PermissionRequest。tool 名と入力の要点を送る
#   notification 入力待ち。message はもともと短文なので要約せずそのまま送る
#   stop         応答完了。人の対応が要るターンだけ Haiku の要約付きで送る
#
# permission モードは **stdout へ何も出してはならない**。PermissionRequest hook の
# stdout は許可判断の入力として解釈されるため、1 バイトでも書くと通知のつもりが
# 自動許可 / 自動拒否になる。背後へ回す処理も stdout を /dev/null へ落として渡す。
#
# webhook URL は $DISCORD_WEBHOOK_URL から読む (正本: ~/.zshenv.local)。
# 未設定なら通知を諦めるだけで、hook は成功扱いで返す。
#
# 要約に使う claude は --safe-mode で起動する。hook / plugin / MCP / CLAUDE.md が
# すべて無効化されるため、この script 自身の再帰起動も観測 plugin の巻き込みも起きない。
# 認証は OAuth (サブスクリプション) がそのまま使われる。

set -uo pipefail

MODE="${1:-stop}"

# 早期 exit する分岐でも先に stdin を読み切る。hook 入力を書いている Claude Code 側に
# EPIPE を返さないため、guard より前に置く。
INPUT=$(cat)

# --safe-mode が hook を無効化するので通常はここに来ないが、多重起動の最終防波堤として残す
if [ -n "${CLAUDE_DISCORD_NOTIFY_CHILD:-}" ]; then
  exit 0
fi

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "discord-notify: DISCORD_WEBHOOK_URL が未設定のため通知を skip した" >&2
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // ""')
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')

COLOR_PERMISSION=16753920
COLOR_WAITING=16705372
COLOR_DONE=5763719

join_lines() {
  local joined="" part=""
  for part in "$@"; do
    [ -z "$part" ] && continue
    if [ -z "$joined" ]; then
      joined="$part"
    else
      joined="$joined
$part"
    fi
  done
  printf '%s' "$joined"
}

transcript_readable() {
  [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]
}

# transcript のメタ行 (ai-title / worktree-state) は session 序盤に 1 回だけ現れるので
# tail の窓では取り逃す。grep で行単位に絞ってから最新行を jq へ渡す。
transcript_meta_line() {
  transcript_readable || return 0
  grep -F "\"type\":\"$1\"" "$TRANSCRIPT" 2>/dev/null | tail -n 1
}

# 最後の人間 prompt の epoch 秒。人間 prompt = type が user で、content に tool_result を
# 含まず、text が `<` (system-reminder / command 展開) で始まらない行。skill 注入の
# "Base directory for this skill:" のような isMeta 行は `<` で始まらず素通りするので別途落とす。
# timestamp はミリ秒付き ISO8601。jq の fromdateiso8601 は小数部を受け付けず、macOS の
# date は ISO8601 を parse できないので、jq 側で小数部を落としてから epoch へ変換する。
last_human_prompt_epoch() {
  transcript_readable || return 0
  grep -F '"type":"user"' "$TRANSCRIPT" 2>/dev/null | jq -r '
    select(.type == "user" and .timestamp != null and ((.isMeta // false) | not))
    | (.message.content // "") as $content
    | select(if ($content | type) == "array"
             then (($content | map(.type) | index("tool_result")) == null)
             else true end)
    | (if ($content | type) == "string"
       then $content
       else ($content | map(select(.type == "text") | .text) | join("\n")) end) as $text
    | select(($text | length) > 0 and ($text | startswith("<") | not))
    | (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)' 2>/dev/null | tail -n 1
}

# $1 以降 (epoch 秒) に記録された pr-link の最新 1 件を Discord リンクにして返す
pr_link_since() {
  transcript_readable || return 0
  grep -F '"type":"pr-link"' "$TRANSCRIPT" 2>/dev/null | jq -r --argjson since "$1" '
    select(.timestamp != null and .prUrl != null)
    | select((.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) >= $since)
    | "[#\(.prNumber // "?")](\(.prUrl))"' 2>/dev/null | tail -n 1
}

# 末尾の assistant text が質問で終わっているか。jq -r は text を複数行で吐くので
# 最後の非空行だけを見れば「末尾が ? か」を判定できる。
last_assistant_text_is_question() {
  transcript_readable || return 1
  local last_line=""
  last_line=$(tail -n 400 "$TRANSCRIPT" | jq -r '
    select(.type == "assistant")
    | ((.message.content // "")
       | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end)
    | sub("[[:space:]]+$"; "")
    | select(length > 0)' 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 1)
  case "$last_line" in
    *'?' | *'？') return 0 ;;
  esac
  return 1
}

field_server() {
  local host="" os="" ip=""
  host=$(hostname -s 2>/dev/null)
  os=$(uname -s 2>/dev/null)
  if [ "$os" = "Darwin" ]; then
    os="macOS"
    ip=$(ipconfig getifaddr en0 2>/dev/null)
  else
    ip=$(ip route get 1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}')
  fi
  printf '%s' "$host${os:+ / $os}${ip:+ / $ip}"
}

# origin があれば [owner/repo](https URL)、無ければ repo ディレクトリ名だけ
field_repo() {
  local remote="" url="" slug="" toplevel=""
  remote=$(git -C "${CWD:-.}" remote get-url origin 2>/dev/null)
  if [ -n "$remote" ]; then
    url=$(printf '%s' "$remote" |
      sed -e 's#^ssh://##' -e 's#^git@\([^:/]*\)[:/]#https://\1/#' -e 's#\.git$##')
    slug=$(printf '%s' "$url" | sed -e 's#^[a-zA-Z+]*://[^/]*/##')
    if [ -n "$slug" ] && [ "$slug" != "$url" ]; then
      printf '[%s](%s)' "$slug" "$url"
      return
    fi
    printf '%s' "$remote"
    return
  fi
  toplevel=$(git -C "${CWD:-.}" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$toplevel" ] && toplevel="$CWD"
  [ -z "$toplevel" ] && return 0
  basename "$toplevel"
}

field_worktree() {
  local state="" name="" branch=""
  state=$(transcript_meta_line "worktree-state")
  if [ -n "$state" ]; then
    name=$(printf '%s' "$state" | jq -r '.worktreeSession.worktreeName // ""' 2>/dev/null)
    branch=$(printf '%s' "$state" | jq -r '.worktreeSession.worktreeBranch // ""' 2>/dev/null)
  fi
  if [ -z "$name" ] && [ -z "$branch" ]; then
    branch=$(git -C "${CWD:-.}" branch --show-current 2>/dev/null)
  fi
  join_lines "$name" "$branch"
}

field_session() {
  local title="" resume=""
  title=$(transcript_meta_line "ai-title" | jq -r '.aiTitle // ""' 2>/dev/null)
  [ -n "$SESSION" ] && resume="\`claude --resume $SESSION\`"
  join_lines "$title" "$resume"
}

# 全モード共通の field を組み立てる。stop の通知条件でも使うので、
# 判定より先に呼んで FIELD_PR / LAST_HUMAN_EPOCH を確定させる。
build_common_fields() {
  LAST_HUMAN_EPOCH=$(last_human_prompt_epoch)
  # 数値以外は「特定できなかった」に倒す。--argjson と算術展開の両方の前提になる
  case "$LAST_HUMAN_EPOCH" in
    '' | *[!0-9]*) LAST_HUMAN_EPOCH="" ;;
  esac
  FIELD_SERVER=$(field_server)
  FIELD_REPO=$(field_repo)
  FIELD_WORKTREE=$(field_worktree)
  FIELD_LOCATION="$CWD"
  FIELD_SESSION=$(field_session)
  FIELD_PR=$(pr_link_since "${LAST_HUMAN_EPOCH:-0}")
}

post_embed() {
  # $1: description  $2: color (decimal)
  jq -n \
    --arg description "$1" \
    --argjson color "$2" \
    --arg server "$FIELD_SERVER" \
    --arg repo "$FIELD_REPO" \
    --arg worktree "$FIELD_WORKTREE" \
    --arg pr "$FIELD_PR" \
    --arg location "$FIELD_LOCATION" \
    --arg session "$FIELD_SESSION" \
    '{embeds: [{
        description: $description,
        color: $color,
        fields: [
          {name: "server", value: $server, inline: true},
          {name: "repo", value: $repo, inline: true},
          {name: "worktree", value: $worktree, inline: true},
          {name: "PR", value: $pr, inline: true},
          {name: "場所", value: $location, inline: false},
          {name: "session", value: $session, inline: false}
        ] | map(select(.value != null and .value != ""))
      }]}' |
    curl -sS --max-time 10 -X POST -H "Content-Type: application/json" \
      -d @- "$DISCORD_WEBHOOK_URL" > /dev/null
}

if [ "$MODE" = "permission" ]; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
  # 丸めは jq の文字単位 slice で行う。head -c は byte 単位のため日本語を含む
  # tool_input を multibyte の途中で切り、不正な UTF-8 が webhook へ渡る。
  TOOL_SUMMARY=$(printf '%s' "$INPUT" | jq -r '
    (try (.tool_input.command // .tool_input.file_path // (.tool_input | tojson)) catch "")
    | if . == null or . == "null" or . == "{}" then "" else tostring end
    | .[0:300]')

  DESCRIPTION="🔐 ${TOOL_NAME:-tool} の許可待ち"
  if [ -n "$TOOL_SUMMARY" ]; then
    # 単一引用符内のバックティックは Discord のコードフェンス。展開させない
    # shellcheck disable=SC2016
    DESCRIPTION=$(printf '%s\n```\n%s\n```' "$DESCRIPTION" "$TOOL_SUMMARY")
  fi

  # 背後の子は hook の stdout fd を握ったままになるので明示的に手放す。
  # dialog を待たせないため、送信完了を待たずに return する。
  {
    build_common_fields
    post_embed "$DESCRIPTION" "$COLOR_PERMISSION"
  } > /dev/null 2>&1 &
  disown
  exit 0
fi

if [ "$MODE" = "notification" ]; then
  MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // "Claude が待っています"')
  # webhook が無応答だと curl の --max-time まで hook がブロックするので背後に回す
  {
    build_common_fields
    post_embed "⏳ $MESSAGE" "$COLOR_WAITING"
  } > /dev/null 2>&1 &
  disown
  exit 0
fi

# --- stop: 条件判定と要約に数秒かかるので hook は即座に返し、残りは背後で完了させる ---
{
  build_common_fields

  # 経過時間が短く、かつ人の対応を促す成果 (PR / 質問) も無いターンは通知しない。
  # 人間 prompt を特定できなかったときは取りこぼしを避けて通知する側へ倒す。
  ELAPSED=-1
  if [ -n "$LAST_HUMAN_EPOCH" ]; then
    ELAPSED=$(($(date +%s) - LAST_HUMAN_EPOCH))
  fi
  SHOULD_NOTIFY=0
  if [ "$ELAPSED" -lt 0 ] || [ "$ELAPSED" -ge "${DISCORD_NOTIFY_STOP_MIN_SECONDS:-120}" ]; then
    SHOULD_NOTIFY=1
  elif [ -n "$FIELD_PR" ] || last_assistant_text_is_question; then
    SHOULD_NOTIFY=1
  fi

  if [ "$SHOULD_NOTIFY" -eq 1 ]; then
    EXCERPT=""
    if transcript_readable; then
      # tool_use / tool_result / system-reminder を捨てて、人間が読む text だけを拾う。
      # tail -n で行単位に切ってから jq に渡す (tail -c は JSON 行を途中で割る)。
      EXCERPT=$(tail -n 400 "$TRANSCRIPT" | jq -r '
        select(.type == "assistant" or .type == "user")
        | ((.message.content // "")
           | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end) as $text
        | select(($text | length) > 0 and ($text | startswith("<") | not))
        | "[\(.message.role // "?")] \($text)"' 2>/dev/null | tail -c 4000)
    fi

    SUMMARY=""
    if [ -n "$EXCERPT" ]; then
      SUMMARY=$(CLAUDE_DISCORD_NOTIFY_CHILD=1 claude -p \
        --safe-mode \
        --model claude-haiku-4-5-20251001 \
        --tools "" \
        --no-session-persistence \
        --system-prompt 'あなたは Claude Code の作業ログ要約器。渡されたログから「何をしたか」を日本語 1〜2 文で要約し、要約文だけを返す。前置き・引用符・箇条書き・見出しは使わない。' \
        "次は Claude Code の作業ログの抜粋。Discord 通知用に要約して。

$EXCERPT" 2>/dev/null | tr -d '\r' | sed '/^$/d' | jq -Rs -r '.[0:1500]')
    fi
    [ -z "$SUMMARY" ] && SUMMARY="応答が完了しました"

    post_embed "✅ $SUMMARY" "$COLOR_DONE"
  fi
} > /dev/null 2>&1 &
disown

exit 0
