## zsh のキーバインドを環境変数 EDITOR に関わらず emacs 風にする
bindkey -e

if which fzf > /dev/null 2>&1; then

    function fzf-select-history() {
        BUFFER=$(\history -n 1 | \
            awk '{ lines[NR]=$0 } END { for (i=NR; i>=1; i--) if (!seen[lines[i]]++) print lines[i] }' | \
            fzf --no-sort --scheme=history --query "$LBUFFER")
        CURSOR=$#BUFFER
        zle reset-prompt
    }
    zle -N fzf-select-history
    bindkey '^r' fzf-select-history

    # cdrの有効化
    if [[ -n $(echo ${^fpath}/chpwd_recent_dirs(N)) && -n $(echo ${^fpath}/cdr(N)) ]]; then
      autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
      add-zsh-hook chpwd chpwd_recent_dirs
      zstyle ':completion:*' recent-dirs-insert both
      zstyle ':chpwd:*' recent-dirs-default true
      zstyle ':chpwd:*' recent-dirs-max 1000
    fi

    function fzf-go-to-dir () {
        local line
        local selected="$(
      {
        (
          autoload -Uz chpwd_recent_filehandler
          chpwd_recent_filehandler && for line in $reply; do
            if [[ -d "$line" ]]; then
              echo "$line"
            fi
          done
        )
        for line in *(-/) ${^cdpath}/*(N-/); do echo "$line"; done | sort -u
      } | fzf --no-sort --query "$LBUFFER"
    )"
        if [ -n "$selected" ]; then
            BUFFER="cd ${(q)selected}"
            zle accept-line
        fi
        zle reset-prompt
    }
    zle -N fzf-go-to-dir
    bindkey '^s' fzf-go-to-dir

    function fzf-preview-file() {
        local file=$(rg --files --hidden --follow --glob '!.git' 2>/dev/null | \
            fzf --height=100% --preview 'bat --color=always {}' --preview-window='right:60%')
        if [ -n "$file" ]; then
            echo -n "$file" | pbcopy
            BUFFER="bat ${(q)file}"
            zle accept-line
        fi
        zle reset-prompt
    }
    zle -N fzf-preview-file
    bindkey '\ep' fzf-preview-file

    function fzf-edit-file() {
        local file=$(rg --files --hidden --follow --glob '!.git' 2>/dev/null | \
            fzf --preview 'bat --color=always --line-range :100 {}')
        if [ -n "$file" ]; then
            BUFFER="${EDITOR:-vim} ${(q)file}"
            zle accept-line
        fi
        zle reset-prompt
    }
    zle -N fzf-edit-file
    bindkey '\eo' fzf-edit-file

    function fzf-grep-copy() {
        local result=$(
            fzf --ansi --disabled \
                --height=100% \
                --delimiter=: \
                --bind "change:reload:rg --line-number --color=always --hidden --glob '!.git' -- {q} 2>/dev/null || true" \
                --preview 'bat --color=always --highlight-line {2} {1} 2>/dev/null' \
                --preview-window='right:60%:+{2}-5'
        )
        if [ -n "$result" ]; then
            local file=$(echo "$result" | cut -d: -f1)
            local line=$(echo "$result" | cut -d: -f2)
            echo -n "${file}:${line}" | pbcopy
            zle -M "Copied: ${file}:${line}"
        fi
        zle reset-prompt
    }
    zle -N fzf-grep-copy
    bindkey '\er' fzf-grep-copy

    ## Ctrl+w で worktree を fzf 選択して切り替え（wt switch）
    function fzf-wt-switch() {
        command -v wt >/dev/null 2>&1 || { zle reset-prompt; return }
        local selected branch
        selected=$(wt list --format json 2>/dev/null \
            | jq -r '.[] | select(.is_current | not) | "\(.branch)\t\(.path)"' \
            | fzf --delimiter='\t' --with-nth=1 --query="$LBUFFER" \
                  --preview 'wt list -C {2}')
        branch=${selected%%$'\t'*}
        if [[ -n $branch ]]; then
            BUFFER="wt switch ${(q)branch}"
            zle accept-line
        fi
        zle reset-prompt
    }
    zle -N fzf-wt-switch
    bindkey '^w' fzf-wt-switch
fi

## C-^ で一つ上のディレクトリへ
function cdup() {
    echo
    cd ..
    echo
    zle reset-prompt
}
zle -N cdup
bindkey '^^' cdup

## Enter押下時の情報表示（accept-lineラップ方式）
## Claude Code内では無効化（ノイズ抑制）
## 2026-05-21: 空Enter時のls+git status自動表示を無効化
# function custom_accept_line() {
#     if [[ -z "$BUFFER" && -z "$CLAUDECODE" ]]; then
#         # 空行の場合、マーカーをセット
#         EMPTY_LINE_ENTER=1
#     else
#         # コマンドがある場合、マーカーをクリア
#         EMPTY_LINE_ENTER=0
#     fi
#     zle .accept-line
# }
# zle -N accept-line custom_accept_line
#
# # コマンド実行後の情報表示
# function precmd_show_info() {
#     if [[ "$EMPTY_LINE_ENTER" == "1" ]]; then
#         echo
#         ls
#         if [ "$(git rev-parse --is-inside-work-tree 2> /dev/null)" = 'true' ]; then
#             echo
#             git status --short --branch
#         fi
#         echo
#     fi
#     # マーカーをリセット
#     EMPTY_LINE_ENTER=0
# }
#
# autoload -Uz add-zsh-hook
# add-zsh-hook precmd precmd_show_info

#cd 後のlsの省略
function chpwd() { [[ -z $CLAUDECODE ]] && ls }

## Ctrl+v でカレントディレクトリをZedで開く
function open-zed() {
    command -v zed >/dev/null 2>&1 && zed .
    zle reset-prompt
}
zle -N open-zed
bindkey '^v' open-zed

# XON/XOFF フロー制御を無効化 (^S / ^Q を通常キーとして解放)。
# ^Q は herdr の prefix。`stty stop undef` は ^S しか解放せず、IXON が有効な限り
# ^Q は XON として tty に食われるため、herdr が受け取る前に shell 側で -ixon が必須。
stty -ixon

## サスペンド無効化
stty susp undef
