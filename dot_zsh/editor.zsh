# ファイル検索 + エディタで開く (rg --files + fzf)
function ef() {
    local file=$(rg --files --hidden --follow --glob '!.git' 2>/dev/null | fzf --preview 'bat --color=always --line-range :100 {}')
    if [ -n "$file" ]; then
        ${EDITOR:-vim} "$file"
    fi
}

# ファイル検索 + 全画面プレビュー + bat出力
function f() {
    local file=$(rg --files --hidden --follow --glob '!.git' 2>/dev/null | \
        fzf --height=100% --preview 'bat --color=always {}' --preview-window='right:60%')
    if [ -n "$file" ]; then
        bat "$file"
    fi
}
