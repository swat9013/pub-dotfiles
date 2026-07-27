
### Aliases ###
#
# linux
#
alias grep='grep --color=auto'
alias ps-grep="ps aux | grep"
alias sed-filename='(){find ./ -type f | sed \"p;s/$1/$2/\" | xargs -n2 mv}'
alias relogin="exec $SHELL -l"

alias diff='diff -u'

#rmtrash
if which rmtrash >/dev/null 2>&1 ;then
    alias rm='rmtrash'
fi

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
    # macOS launchd ssh-agent は idle で kill され、再起動後は空になる。
    # かつ Apple-OpenSSH は UseKeychain 経由で読んだ鍵を agent に乗せない。
    # → precmd で「id_rsa が agent に無ければ keychain から再ロード」する。
    _ssh_ensure_id_rsa() {
        ssh-add -l 2>/dev/null | grep -q "id_rsa " || \
            ssh-add --apple-use-keychain --quiet "$HOME/.ssh/id_rsa" 2>/dev/null
    }
    _ssh_ensure_id_rsa
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _ssh_ensure_id_rsa
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
alias ld='ls -ld'          # Show info about the directory
alias less="less -qnR"
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

#
# wtp (git worktree)
#
command -v wtp >/dev/null 2>&1 && eval "$(wtp shell-init zsh)"
