# ghq + fzf 連携設定

# ghq + fzfでリポジトリを選択してcd（最近アクセスしたリポジトリを優先表示）
function ghq-fzf() {
    local ghq_root="$(ghq root)"
    local repo=$(
        {
            autoload -Uz chpwd_recent_filehandler
            chpwd_recent_filehandler
            for dir in $reply; do
                if [[ "$dir" == "$ghq_root"/* ]]; then
                    echo "${dir#$ghq_root/}"
                fi
            done
            ghq list
        } | awk '!seen[$0]++' | fzf
    )
    if [ -n "$repo" ]; then
        cd "$ghq_root/$repo"
    fi
}

# エイリアス
alias gf='ghq-fzf'
alias gg='ghq get'
