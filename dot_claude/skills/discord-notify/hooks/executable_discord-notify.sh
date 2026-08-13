#!/bin/bash
# Claude Code の hook から呼ばれ、Discord webhook へ通知を送る。
#
#   permission   PermissionRequest。tool 名と入力の要点を送る
#   notification 入力待ち。message はもともと短文なので要約せずそのまま送る
#   stop         応答完了。人の対応が要るターンだけ「次のアクション + 要約」を送る
#
# stop 通知の先頭に置く「次のアクション」は、script が検証できる事実 — PR の有無 /
# 末尾が質問か / working tree の状態 — だけから決める。要約 LLM に行動を書かせると
# 抜粋に無い作業を捏造する (「テストを実行してください」等) ため、LLM の担当は
# 「何をしたか」の要約に限る。行動を特定できないターンは行動を捏造せず、
# そもそも通知を送らない。
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

COLOR_PERMISSION=16753920
COLOR_WAITING=16705372

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

# $1 を $2 文字で丸める。head -c は byte 単位のため日本語を multibyte の途中で切り、
# 不正な UTF-8 が webhook へ渡る。丸めは jq の文字単位 slice で行う。
truncate_text() {
  printf '%s' "$1" | jq -Rs -r --argjson n "$2" '.[0:$n]'
}

transcript_readable() {
  [ -n "${TRANSCRIPT:-}" ] && [ -r "$TRANSCRIPT" ]
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

# 末尾 assistant text の最後の非空行。「質問で終わったか」の判定と、通知に載せる
# 質問文の引用の両方がこれ 1 本で足りる (jq -r は text を複数行で吐くので、
# 末尾が `?` かは最後の非空行だけを見れば判定できる)。
last_assistant_tail_line() {
  transcript_readable || return 0
  tail -n 400 "$TRANSCRIPT" | jq -r '
    select(.type == "assistant")
    | ((.message.content // "")
       | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end)
    | sub("[[:space:]]+$"; "")
    | select(length > 0)' 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 1
}

# 未 commit のファイル数 (untracked を含む)。新規作成した file も成果物なので数える。
# git repo の外では何も出さない — 「0 件」と「判定不能」を区別する必要はここには無いが、
# 数を通知文に載せる以上、数えられなかったものを 0 と偽らない。
uncommitted_file_count() {
  git -C "${CWD:-.}" rev-parse --is-inside-work-tree > /dev/null 2>&1 || return 0
  git -C "${CWD:-.}" status --porcelain 2>/dev/null | grep -c '^' | tr -d ' '
}

# 送り先より先行している commit 数。基準は上から順に決める:
#
#   1. upstream。設定済みなら最も正確
#   2. origin/<branch>。`git push origin <branch>` を -u 無しで打つと upstream は
#      空のままだが remote には存在する。ここを見ないと push 済みの branch へ
#      「push しろ」と言い続ける
#   3. 一度でも push された形跡 (branch.<name>.merge) があるのに 1 も 2 も無い場合は
#      remote 側が消えた後 (merge 済み等)。基準を作らず黙る
#   4. origin/HEAD = 既定 branch。一度も push していない branch はこれが基準になり、
#      「push して PR を作る」が正しい行動になる
#
# detached HEAD は push 先の branch が無いので数えない。基準を決められなければ何も
# 出さない — 「先行 0」と「判定不能」を同じ空文字に倒し、行動の捏造を避ける。
unpushed_commit_count() {
  local branch="" base=""
  branch=$(git -C "${CWD:-.}" symbolic-ref --quiet --short HEAD 2>/dev/null)
  [ -z "$branch" ] && return 0

  base=$(git -C "${CWD:-.}" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [ -z "$base" ] &&
    git -C "${CWD:-.}" rev-parse --verify --quiet "refs/remotes/origin/$branch" > /dev/null 2>&1; then
    base="origin/$branch"
  fi
  if [ -z "$base" ]; then
    [ -n "$(git -C "${CWD:-.}" config --get "branch.$branch.merge" 2>/dev/null)" ] && return 0
    base=$(git -C "${CWD:-.}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  fi

  [ -z "$base" ] && return 0
  git -C "${CWD:-.}" rev-list --count "$base..HEAD" 2>/dev/null
}

# stop 通知の先頭 1 行。「人が次に何をするか」を検証済みの事実だけから決める。
#   $1 PR リンク ("" なら PR 無し) / $2 末尾 assistant 行
#   $3 未 commit ファイル数 / $4 未 push commit 数 (どちらも "" は判定不能)
# 優先順は「人にしかできない判断が要る順」。どれにも該当しなければ行動を作らず、
# 👀 で始まる行を返す。呼び出し側はこれを通知抑止の合図として使う。
#
# 差分バケットの文面は「レビューする」に留める。ターンの途中で止まっているのか
# 作業を終えたのかは script からは分からず、commit を促すと前者で嘘になる。
# どちらであっても人がすることは「変更を見る」で変わらない。
action_line() {
  local pr="$1" tail_line="$2" dirty="$3" ahead="$4"
  if [ -n "$pr" ]; then
    printf '👉 **PR をレビューして merge する** — %s' "$pr"
    return
  fi
  case "$tail_line" in
    *'?' | *'？')
      printf '👉 **質問に回答する**\n> %s' "$(truncate_text "$tail_line" 300)"
      return
      ;;
  esac
  case "$dirty" in
    '' | 0 | *[!0-9]*) ;;
    *)
      printf '👉 **未 commit の %s ファイルをレビューする**' "$dirty"
      return
      ;;
  esac
  case "$ahead" in
    '' | 0 | *[!0-9]*) ;;
    *)
      printf '👉 **未 push の commit %s 件を push して PR を作る**' "$ahead"
      return
      ;;
  esac
  printf '👀 **対応不要** — 結果だけ確認する'
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

# scripts/test/shell/test-discord-notify.sh が関数だけを取り込むための seam。
# 定義が済んだ時点で戻り、stdin の読み取りにも通知本体にも入らない。
# source されていれば return で抜ける。直接実行されていた場合は return が失敗するので
# exit へ落とす (shellcheck からは到達不能に見えるが、実行経路の違いで到達する)。
if [ -n "${DISCORD_NOTIFY_SOURCE_ONLY:-}" ]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi

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

if [ "$MODE" = "permission" ]; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
  # 丸めは truncate_text と同じ理由で jq の文字単位 slice。ここは既に tool_input を
  # jq で開いている途中なので、同じ pipeline 内で切る
  TOOL_SUMMARY=$(printf '%s' "$INPUT" | jq -r '
    (try (.tool_input.command // .tool_input.file_path // (.tool_input | tojson)) catch "")
    | if . == null or . == "null" or . == "{}" then "" else tostring end
    | .[0:300]')

  DESCRIPTION="🔐 **${TOOL_NAME:-tool} の実行を許可 / 拒否する**"
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
    post_embed "$(printf '⏳ **Claude に応答する**\n%s' "$MESSAGE")" "$COLOR_WAITING"
  } > /dev/null 2>&1 &
  disown
  exit 0
fi

# --- stop: 条件判定と要約に数秒かかるので hook は即座に返し、残りは背後で完了させる ---
{
  build_common_fields
  TAIL_LINE=$(last_assistant_tail_line)

  # 経過時間が短く、かつ人の対応を促す成果 (PR / 質問) も無いターンは通知しない。
  # 人間 prompt を特定できなかったときは gate だけは通す側へ倒す。ただしその先の
  # 行動判定で 👀 になれば結局送らない — transcript も git 状態も手掛かりが無い
  # ターンは「やることがある」と言い切れないので、鳴らさない側が正しい。
  ELAPSED=-1
  if [ -n "$LAST_HUMAN_EPOCH" ]; then
    ELAPSED=$(($(date +%s) - LAST_HUMAN_EPOCH))
  fi
  SHOULD_NOTIFY=0
  if [ "$ELAPSED" -lt 0 ] || [ "$ELAPSED" -ge "${DISCORD_NOTIFY_STOP_MIN_SECONDS:-120}" ]; then
    SHOULD_NOTIFY=1
  elif [ -n "$FIELD_PR" ]; then
    SHOULD_NOTIFY=1
  else
    case "$TAIL_LINE" in
      *'?' | *'？') SHOULD_NOTIFY=1 ;;
    esac
  fi

  # gate を越えても、人がすることが無いターン (action_line が 👀 を返す) は通知しない。
  # 経過時間だけを理由に鳴る「やることは無い」通知が実測で全体の約 4 割を占めるため、
  # 行動が特定できたターンだけに絞る。
  ACTION=""
  DIRTY_COUNT=""
  AHEAD_COUNT=""
  if [ "$SHOULD_NOTIFY" -eq 1 ]; then
    DIRTY_COUNT=$(uncommitted_file_count)
    AHEAD_COUNT=$(unpushed_commit_count)
    ACTION=$(action_line "$FIELD_PR" "$TAIL_LINE" "$DIRTY_COUNT" "$AHEAD_COUNT")
    case "$ACTION" in
      '👀'*) SHOULD_NOTIFY=0 ;;
    esac
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

    # 「ロックを Service と Repository のどちらに置くか決める」のような、git の状態
    # だけでは出せない粒度の行動は Haiku にログを読ませないと出ない。捏造の余地は
    # <facts> で塞ぐ — 判定済みの事実を渡し、それとログ以外を根拠にさせない。
    #
    # facts に置くのは観測値だけで、決定的に組み立てた行動文 ($ACTION) は渡さない。
    # 渡すとログ中の本当の判断より優先して丸写しされる (3 案の選択を落として
    # 「未 commit のファイルをレビューする」を返す挙動が実測で再現した)。
    FACTS=$(printf 'PR: %s\n未 commit のファイル: %s\n未 push の commit: %s' \
      "${FIELD_PR:-このターンでは作られていない}" \
      "${DIRTY_COUNT:-判定できなかった}" \
      "${AHEAD_COUNT:-判定できなかった}")

    JUDGED=""
    if [ -n "$EXCERPT" ]; then
      JUDGED=$(CLAUDE_DISCORD_NOTIFY_CHILD=1 claude -p \
        --safe-mode \
        --model claude-haiku-4-5-20251001 \
        --tools "" \
        --no-session-persistence \
        --system-prompt 'あなたは Claude Code の作業ログを読み、通知を受け取る本人が次に何をすべきかを日本語で書く。

ログの中から、本人にしか決められないこと — 判断・選択・方針・質問への回答 — を探してそれを行動にする。作業の続きは Claude が進められるので行動にしない。本人が決めない限り前に進まないものだけが行動になる。ログにそういう箇所が無ければ <facts> の状態から最も具体的な行動を 1 つ書く。

行動は命令形 1 文で書く。判断の根拠が要るならもう 1 文だけ添える。行動も根拠も常体 (「〜する」「〜だ」) で書く。前置き・見出し・箇条書き・引用符は使わない。

<log> と <facts> は本人が見ていない入力なので、タグ名を文中に出さず、中身だけを自分の言葉で書く。

根拠にしてよいのは <facts> とログに現れた事実だけ。根拠の無い作業を書くと、本人は存在しない問題を追うことになる。

PR に触れるときは <facts> のリンク記法をそのまま使う。本人が Discord からそのまま開けるようにするため。

<example>
落ちているテストの修正方針を決める。ロックを Service と Repository のどちらに置くかで実装が変わり、原因の特定までは終わっている。
</example>
<example>
3 案のどれで進めるかを選ぶ。評価は出そろっていて、残るのはプロダクト側の重み付けだけ。
</example>
<example>
[#139](https://github.com/example/repo/pull/139) をレビューして merge する。
</example>
<example>
未 commit の 12 ファイルをレビューする。
</example>
<example>
未 commit の 1 ファイルを確認する。ログからは本人の判断が要る箇所を読み取れなかった。
</example>' \
        "<log>
$EXCERPT
</log>

<facts>
$FACTS
</facts>

上のログを読み、通知を受け取る本人が次に何をすべきかを書け。" 2>/dev/null |
        tr -d '\r' | sed '/^$/d' | jq -Rs -r '.[0:1500]')
    fi

    # Haiku が何も返さなかったときは、検証済みの事実だけで作った行動文へ落とす
    # (こちらは絵文字を持っているので前置きしない)
    if [ -n "$JUDGED" ]; then
      DESCRIPTION=$(printf '👉 %s' "$JUDGED")
    else
      DESCRIPTION="$ACTION"
    fi

    # ここへ来る stop 通知は必ず要対応。色は待ち状態の 1 色で足りる
    post_embed "$DESCRIPTION" "$COLOR_WAITING"
  fi
} > /dev/null 2>&1 &
disown

exit 0
