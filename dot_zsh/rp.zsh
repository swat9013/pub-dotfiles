# rp（~/.local/bin/rp）のサブコマンド補完

function _rp() {
    local -a subcmds=(
        'issue-list:open な issue を fzf で選び、ブラウザで開く'
        'issue-open:issue 一覧ページをブラウザで開く'
        'cl-list:open な CL を fzf で選び、ブラウザで開く'
        'cl-open:今いるブランチの CL をブラウザで開く'
    )
    _describe 'rp command' subcmds
}
compdef _rp rp
