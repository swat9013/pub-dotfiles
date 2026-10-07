
### Aliases ###
#
# linux
#
alias ps-grep="ps aux | grep"
alias sed-filename='(){find ./ -type f | sed \"p;s/$1/$2/\" | xargs -n2 mv}'
alias relogin="exec $SHELL -l"

#
# editor
#
alias emacs-kill-force='pkill -9 emacs'

# emacs を TTY で fresh 起動する。
# 2026-05-22: daemon/emacsclient を廃止 (Emacs 30 起動 0.48s で当初の高速化目的が消失、
# かつ daemon 経由だと clipetty の OSC52 emit や terminfo 伝播の罠を踏みやすい)。
function e() {
    emacs -nw "$@"
}

#
# ssh
#
if [[ "$(uname)" == 'Darwin' ]]; then
    # 鍵の agent 投入は shell 起動時に自動化しない。投入した鍵が session 中に
    # 消える根本原因が未特定で、起動時に何を投入しても使用時には空になりうる。
    # ssh -A を使う直前に ssh-aa で投入するのが唯一確実な運用。
    # 手動再投入用 (新規 agent を起動しない macOS 安全版)
    alias ssh-aa='ssh-add --apple-use-keychain ~/.ssh/id_rsa'
else
    alias ssh-aa='eval `ssh-agent -s` ; ssh-add'
fi
alias sshdir='cd ~/.ssh'

#
# herdr
#
alias ide="~/.config/herdr/layouts/ide.sh"

#
# git
#
alias -g L='`git log --decorate --oneline | fzf | cut -d" " -f1`'
alias -g LA='`git log --decorate --oneline --all | fzf | cut -d" " -f1`'
alias -g R='`git reflog | fzf | cut -d" " -f1`'

#
# ls
#
alias lr='ls -lR'          # Recursive ls
alias lt='ls -ltr'         # Sort by date, most recent last
alias lu='ls -ltur'        # Sort by and show access time, most recent last
alias lx='ls -lXB'         # Sort by extension
alias l='ls -1F'           # Show long file information
alias ll='ls -lF'          # Long listing
alias la='ls -AF'          # Show hidden files
alias lc='ls -ltcr'        # Sort by and show change time, most recent last
alias lk='ls -lShr'         # Sort by size, biggest last
alias lla='ls -lAF'        # Show hidden all files

#
# marp
#
alias marp-convert-pdf='docker run --rm --init -v $PWD:/home/marp/app/ -e LANG=$LANG marpteam/marp-cli --allow-local-files --html --pdf $*'
alias marp-w='docker run --rm --init -v $PWD:/home/marp/app/ -e LANG=$LANG -p 37717:37717 marpteam/marp-cli -w --html $*'

#
# ruby
#
alias rubo-branch='rubocop -a --force-exclusion $(git diff --name-only --diff-filter=AMRC origin/master HEAD) $(git status --porcelain | grep -v "^ D " | sed s/^...//)'

#
# rails
#
alias con='docker-compose run --rm web bundle exec rails c'
alias db_migrate='rake db:migrate'
alias db_rollback='rake db:rollback'

#
# docker
#
alias dcew='docker-compose exec web'
alias dcewtest='docker-compose exec web rails test'
alias dclog='COMPOSE_HTTP_TIMEOUT=30000 docker-compose logs -f'
alias dcr='docker-compose run --rm'
alias dcrw='docker-compose run --rm web'
alias dcrw-rails='docker-compose run --rm web bundle exec rails'
alias dcrwrubo-branch='docker-compose run --rm web bundle exec rubocop -a --force-exclusion $(git diff --name-only --diff-filter=AMRC origin/master HEAD) $(git status --porcelain | grep -v "^ D " | sed s/^...//)'
alias dcrwrubo-cache='docker-compose run --rm web bundle exec rubocop -a --force-exclusion $( git diff --cached --name-only)'
alias dcrwrubo-diff='docker-compose run --rm web bundle exec rubocop -a --force-exclusion $( git diff --name-only --diff-filter=AMRC)'
alias dcrwrubo-status='docker-compose run --rm web bundle exec rubocop -a --force-exclusion $( git status --porcelain | grep -v "^ D " | sed s/^...// | paste -s -)'
alias dcrwrubo='docker-compose run --rm web bundle exec rubocop -a'
alias dcrwtest='docker-compose run --rm web bundle exec rails test'
alias dcud='docker-compose up -d'
alias attach='docker attach webapplication_web_1'
alias up='docker-compose up -d'
alias stop='docker-compose stop'
alias docker-stop-all='docker stop $(docker ps -q)'

#
# repository scripts
#
alias lint="./script/lint.sh"
alias build="./script/build.sh"
alias setup="./script/setup.sh"

#
# AI Coding
#
alias cc='claude'
alias cca='claude --permission-mode auto'
alias cco='claude --model opus'
alias ccp='claude --setting-sources project,local'  # user設定を除外してプロジェクト+ローカルのみ適用
alias ccpa='claude --setting-sources project,local --permission-mode auto'
alias ccps='claude --setting-sources project,local --model sonnet'
alias ccs='claude --model sonnet'
alias cch='claude --model haiku'
alias ccid='claude --model sonnet --effort xhigh "/issue-dispatch"'  # 対話モードで /issue-dispatch を初期プロンプトに投入

# Remote Control のセッション名を cwd から組み立てて標準出力へ返す（先頭ドットは落とす）
# Example: repo → myapp / その worktree → myapp-i3 / 非git → カレントディレクトリ名
_cc_session_name() {
    local root name
    root=$(git rev-parse --show-toplevel 2>/dev/null)

    if [[ -z $root ]]; then
        name=${PWD:t}
    else
        # --git-common-dir は linked worktree では main tree の .git（絶対）、main tree では ".git"（相対）
        local common=$(git rev-parse --git-common-dir)
        [[ $common == /* ]] || common="$root/$common"
        local main=${${common:A:h}:t}

        name=$main
        [[ ${root:t} != "$main" ]] && name="$main-${root:t}"
    fi

    print -r -- "${name#.}"
}

# Remote Control を有効にして起動。セッション名にリポジトリ名を付ける
# Usage: ccr [claude options...]
function ccr() {
    # --remote-control は値が省略可能なため、= 形式で名前を確実に束縛する
    claude --remote-control="$(_cc_session_name)" "$@"
}

# dispatch の orchestrator を cwd = project の anchor repo で起こす（swat-skills の起動規約に対応）
# Usage: cc-orc [max]   max = 同時稼働 worker 数の上限（省略時は skill 側の既定 3）
# model / effort は下の claude 行で固定
# Remote Control のセッション名は <repo>-orchestrator（claude.ai の一覧で project を判別するため）。
# agent 名は orchestrator で固定（project に 1 体・固定名の役職名で、worker からの宛先になる）
function cc-orc() {
    # herdr の外でも claude は起動するが dispatch-ops の前提検査に落ちるので先に切る
    if [[ $HERDR_ENV != 1 ]]; then
        print -u2 "cc-orc: herdr session の外です。herdr session 内で実行してください"
        return 1
    fi
    # anchor は起動時の cwd（規約の正本は swat-skills README）。誤った cwd は別 project の
    # durable 台帳を無言で新設するため、repo root であることだけ検査する（どの repo が
    # 正しい anchor かは関数には判定できず、規約どおり起動者の責任に残す）
    if [[ "$(git rev-parse --show-toplevel 2>/dev/null)" != "${PWD:A}" ]]; then
        print -u2 "cc-orc: cwd が git repo の root ではありません。project の anchor repo 直下で実行してください"
        return 1
    fi

    # 受け取るのは max だけ。余剰引数を黙って捨てず、prompt へ紛れ込ませもしない
    if (( $# > 1 )); then
        print -u2 "cc-orc: 引数は max のみです（claude の option は渡せません）"
        return 1
    fi

    # `prompt` は zsh の PS1 と束ねられた特殊変数なので local に取らない
    local initial_prompt="/swat-skills:orchestrator"
    (( $# )) && initial_prompt+=" $1"

    # opus は常駐中の指示追従の忠実さ（規約と罠の表を崩さない）を買うため。
    # effort が medium なのは worker の質問中継が turn の大半で、粘りより応答性が効くから
    claude --model opus --effort medium \
        --remote-control="$(_cc_session_name)-orchestrator" --name orchestrator "$initial_prompt"
}

# 軽量Claude Codeでワンライナー質問（ファイル参照オプション対応）
# Usage: ccask "質問内容" [file1] [file2] ...
# Example:
#   ccask "このコードを説明して" main.py
#   ccask "これらのファイルの違いは？" old.js new.js
#   ccask "今日の日付は？"
function ccask() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: ccask \"質問内容\" [file1] [file2] ..."
        echo "Example: ccask \"このコードを説明して\" main.py"
        return 1
    fi

    local prompt="$1"
    shift

    # ファイル引数があれば内容を追加
    if [[ $# -gt 0 ]]; then
        local file_contents=""
        for file in "$@"; do
            if [[ -f "$file" ]]; then
                file_contents="${file_contents}
--- ${file} ---
$(cat "$file")
"
            else
                echo "Warning: '$file' is not a file, skipping." >&2
            fi
        done

        if [[ -n "$file_contents" ]]; then
            prompt="${prompt}

${file_contents}"
        fi
    fi

    claude --model haiku -p "$prompt"
}
