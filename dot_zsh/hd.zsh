# hd: herdr session を ローカル / SSH 先 で冪等に attach するラッパー。
#
# Usage:
#   hd                     # ローカル: basename(PWD) を session 名に herdr --session
#   hd <session>           # ローカル: 明示 session 名で attach or 新規
#   hd @<host> [session]   # リモート: ssh -t で接続し remote 上で herdr を直接実行
#
# @host が `herdr --remote` ではなく ssh + remote herdr 直接実行なのは意図的。
# v0.7.4 の --remote (Mac client ↔ ssh bridge ↔ remote server) には popup 不描画と
# prefix 後キー照合の不安定という 2 つの upstream bug があり、client/server を remote
# 同一ホストに置く ssh 直接実行はその経路自体を通らない。
#
# 実装メモ:
# - keepalive (ServerAlive*) は手書きオプションで付与する。旧 --remote 時代の
#   [remote] manage_ssh_config = true 委譲は ssh 直接実行では働かない。
# - remote herdr の存在チェックは remote コマンド内で行う (事前 ssh チェックと同じ意図を
#   接続 1 回で実現)。herdr は ~/.local/bin 配置前提 (旧 --remote の自動インストール先) で
#   ssh 非対話 PATH に無い可能性があるため、shell/path-prepend.sh と同じ流儀で PATH を自前
#   prepend する (共有 primitive は ssh command 文字列内で remote 実行され source 不可なため inline)。
# - session 名の '.' ':' → '_' 置換を行う (session id として安全な文字集合に正規化)。
# HD_DRY_RUN=1 を立てると実行せず、組み立てた実行予定コマンドを stdout に print する
# (テスト用の契約)。

hd() {
  local target="${1:-}"

  if [[ "$target" == @* ]]; then
    local host="${target#@}"
    if [[ -z "$host" ]]; then
      print -u2 -- "usage: hd @<host> [session]"
      return 2
    fi

    # session 引数省略時はローカル hd の引数省略時と同じ規則 (basename(PWD) を
    # sanitize) を remote 側で評価する。ssh 直後の PWD は remote の $HOME。
    local herdr_cmd
    if [[ -n "${2:-}" ]]; then
      local session="${2//[.:]/_}"
      herdr_cmd="exec herdr --session ${(q-)session}"
    else
      herdr_cmd='exec herdr --session "$(basename -- "$PWD" | tr ".:" "__")"'
    fi

    # ssh <host> <cmd> は login shell の -c 非対話実行で、対話 zsh の初期化
    # (dot_zshrc の PATH 追加 / keybinds.zsh の stty -ixon) を一切通らない。
    # 1. PATH: herdr が非対話 PATH に無い可能性があるため ~/.local/bin を prepend し、
    #    それでも見つからなければ明示エラーで 127 を返す。
    # 2. stty -ixon: herdr は shell 側で ^Q (XON) を解放済みの tty を前提とする。
    #    sshd が確保する pty は IXON 有効のままなので、明示解放しないと prefix の
    #    ^Q が XON として tty ドライバに食われ herdr に届かない。
    local remote_cmd="export PATH=\"\$HOME/.local/bin:\$PATH\"; command -v herdr >/dev/null 2>&1 || { echo \"hd: remote host ${host} lacks herdr in PATH or ~/.local/bin\" >&2; exit 127; }; stty -ixon; ${herdr_cmd}"

    if [[ -n "${HD_DRY_RUN:-}" ]]; then
      print -- "myssh -t -o ServerAliveInterval=5 -o ServerAliveCountMax=3 ${host} ${remote_cmd}"
      print -- "_term_reset_modes  # 復帰時に端末モード解除 (異常切断の残留マウス報告対策)"
      return 0
    fi
    # 関数終了時に端末モード解除 (Ctrl+C / 正常 / 異常切断いずれでも)。
    # ServerAlive* で断を ~15 秒で検知 → ssh が return → 残留マウス報告モードを解除する。
    trap "_term_reset_modes" EXIT INT TERM
    myssh -t -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "$host" "$remote_cmd"
    _term_reset_modes
    trap - EXIT INT TERM
    return
  fi

  local raw="${target:-${PWD:t}}"
  local session="${raw//[.:]/_}"

  if [[ -n "${HD_DRY_RUN:-}" ]]; then
    print -- "herdr --session ${(q-)session}"
    return 0
  fi
  herdr --session "$session"
}

# herdr 純正の zsh 補完 (herdr コマンド用)。実測 13.5ms が起動 hot path に乗っていたため
# (#120)、fpath 化ではなく共有 primitive cache_eval に寄せた。1 行のままで fork が消える。
command -v herdr >/dev/null && cache_eval herdr herdr completion zsh

# hd ラッパー用の補完: `@` prefix 消費で ssh host 補完、それ以外は herdr session 名補完。
# ssh host 収集は sshfs.zsh の _sshmount_collect_hosts をそのまま流用する
# (Include 再帰 + glob 展開 + ワイルドカードホスト除外を実装済み)。
# @host の第 2 引数 (remote session 名) は補完しない (列挙に ssh 接続が要るため)。
_hd() {
  (( CURRENT == 2 )) || return
  if compset -P '@'; then
    local -a hosts
    hosts=( ${(f)"$(_sshmount_collect_hosts)"} )
    _describe -t hosts 'ssh host' hosts
  else
    local -a sessions
    sessions=( ${(f)"$(herdr session list --json 2>/dev/null | jq -r '.sessions[].name' 2>/dev/null)"} )
    _describe -t sessions 'herdr session' sessions
  fi
}
compdef _hd hd
