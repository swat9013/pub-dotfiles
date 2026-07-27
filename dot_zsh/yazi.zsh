# Yazi統合設定

# cd on quit機能 - yaziで移動したディレクトリにシェルも移動
function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    command yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

# ghqリポジトリルートでyaziを起動
function yg() {
    if ! which ghq > /dev/null 2>&1; then
        echo "Error: ghq is not installed"
        return 1
    fi

    local ghq_root="$(ghq root)"
    if [ -n "$ghq_root" ]; then
        y "$ghq_root"
    else
        echo "Error: ghq root not configured"
        return 1
    fi
}

# ghqリポジトリ一覧からfzfで選択してyaziで開く
function ygh() {
    if ! which ghq > /dev/null 2>&1; then
        echo "Error: ghq is not installed"
        return 1
    fi

    if ! which fzf > /dev/null 2>&1; then
        echo "Error: fzf is not installed"
        return 1
    fi

    local repo=$(ghq list | fzf)
    if [ -n "$repo" ]; then
        y "$(ghq root)/$repo"
    fi
}

# エイリアス
alias yazi='y'  # 常にcd on quit機能付きで起動
