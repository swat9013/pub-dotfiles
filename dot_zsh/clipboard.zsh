# pbcopy/pbpaste 互換 (Linux/WSL2 で macOS と同じ呼び出しを許す)
# .zsh/keybinds.zsh の fzf-* 関数が pbcopy を直接呼ぶため、
# 非macOS環境では適切なバックエンドへ alias する。

if ! command -v pbcopy >/dev/null 2>&1; then
    if command -v clip.exe >/dev/null 2>&1; then
        alias pbcopy='clip.exe'
    elif command -v wl-copy >/dev/null 2>&1; then
        alias pbcopy='wl-copy'
    elif command -v xclip >/dev/null 2>&1; then
        alias pbcopy='xclip -selection clipboard'
    fi
fi

if ! command -v pbpaste >/dev/null 2>&1; then
    if command -v powershell.exe >/dev/null 2>&1; then
        alias pbpaste='powershell.exe -NoProfile -Command Get-Clipboard'
    elif command -v wl-paste >/dev/null 2>&1; then
        alias pbpaste='wl-paste'
    elif command -v xclip >/dev/null 2>&1; then
        alias pbpaste='xclip -selection clipboard -o'
    fi
fi
