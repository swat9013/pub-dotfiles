
### SSHFS (FUSE-T backend) ###
# macOS で kext 非依存にリモートディレクトリをマウントする wrapper。
# 前提: brew install --cask fuse-t && brew install macos-fuse-t/homebrew-cask/sshfs-fuse-t
#
# Usage:
#   sshmount <user@host:/remote/path> <local/mount/point>
#   sshmount spica-app:/var/www/app ./mount
#   sshumount [-f|--force] <local/mount/point>
#   sshmount-ls           # 現在マウント中の sshfs/fuse-t 一覧
#   sshmount-kill [path]  # 緊急停止: sshfs プロセスを SIGKILL

function sshmount() {
    if [[ $# -ne 2 ]]; then
        echo "Usage: sshmount <user@host:/remote/path> <local/mount/point>" >&2
        return 2
    fi

    local remote="$1"
    local mountpoint="$2"

    if ! command -v sshfs >/dev/null 2>&1; then
        echo "sshfs not found. Install:" >&2
        echo "  brew install --cask fuse-t" >&2
        echo "  brew install macos-fuse-t/homebrew-cask/sshfs-fuse-t" >&2
        return 127
    fi

    [[ -d "$mountpoint" ]] || mkdir -p "$mountpoint" || return 1

    # :a は純粋な文字列操作で絶対パス化する (stat() を呼ばない)。
    # 壊れた FUSE mount 上で cd/pwd するとブロックするため、必ず :a を使う。
    local abs_mount="${mountpoint:a}"
    if mount | grep -qE " on ${abs_mount} "; then
        echo "already mounted: $abs_mount" >&2
        return 0
    fi

    # BatchMode=yes / NumberOfPasswordPrompts=0: 回線断時に認証プロンプトを出さない
    #   → macFUSE / FUSE-T の "connection failed" popup が連発するのを防ぐ
    # ConnectTimeout=5 / ConnectionAttempts=1: 各再接続を短時間で failfast させる
    # reconnect + ServerAlive*: スリープ復帰や一時的な回線断で自動再接続
    # defer_permissions: NFS 層のパーミッション矛盾を回避
    # auto_cache: mtime/size 変化で自動キャッシュ無効化
    sshfs "$remote" "$mountpoint" \
        -o volname="${mountpoint:t}" \
        -o defer_permissions \
        -o follow_symlinks \
        -o auto_cache \
        -o reconnect \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=3 \
        -o ssh_command="ssh -oBatchMode=yes -oNumberOfPasswordPrompts=0 -oConnectTimeout=5 -oConnectionAttempts=1"
}

function sshumount() {
    local force=0
    while [[ "$1" == -* ]]; do
        case "$1" in
            -f|--force) force=1; shift ;;
            --) shift; break ;;
            *) echo "unknown option: $1" >&2; return 2 ;;
        esac
    done

    if [[ $# -ne 1 ]]; then
        echo "Usage: sshumount [-f|--force] <local/mount/point>" >&2
        return 2
    fi

    # :a は stat() を呼ばない絶対パス化。壊れた mount 上での cd ハングを回避する。
    local abs_mount="${1:a}"

    if (( force )); then
        # 通常の umount は FUSE bridge が反応しない時ハングするため、
        # sshfs プロセスを直接 SIGKILL → カーネル側 mount を diskutil で強制解除する
        local -a pids
        pids=( ${(f)"$(pgrep -f "sshfs.*${abs_mount}" 2>/dev/null)"} )
        if (( ${#pids} )); then
            echo "killing sshfs pids: ${pids[*]}" >&2
            kill -KILL "${pids[@]}" 2>/dev/null
            sleep 1
        fi
        diskutil unmount force "$abs_mount" 2>/dev/null \
            || umount -f "$abs_mount" 2>/dev/null \
            || { echo "force unmount failed: $abs_mount" >&2; return 1; }
        return 0
    fi

    if ! mount | grep -qE " on ${abs_mount} "; then
        echo "not mounted: $abs_mount (try: sshumount -f $1)" >&2
        return 1
    fi

    umount "$abs_mount" 2>/dev/null || diskutil unmount force "$abs_mount"
}

function sshmount-ls() {
    # FUSE-T のマウントは NFS 層として表示されるため、
    # 「@ を含み remote path を持つ NFS」を sshfs マウントとみなす。
    mount | awk '/@.* on .* \(nfs/ || /fuse.?t/ || /osxfuse/ || /macfuse/'
}

# 緊急停止コマンド。sshumount -f がハングした / mount point 不明な状況で使う。
# 引数なし: 全 sshfs プロセスを SIGKILL
# 引数あり: 指定 mount path にマッチする sshfs プロセスだけを SIGKILL
function sshmount-kill() {
    local -a pids
    if [[ $# -eq 0 ]]; then
        pids=( ${(f)"$(pgrep -f 'sshfs' 2>/dev/null)"} )
    else
        local abs_mount="${1:a}"
        pids=( ${(f)"$(pgrep -f "sshfs.*${abs_mount}" 2>/dev/null)"} )
    fi
    if (( ${#pids} == 0 )); then
        echo "no sshfs process found" >&2
        return 1
    fi
    echo "killing sshfs pids: ${pids[*]}" >&2
    kill -KILL "${pids[@]}" 2>/dev/null
    # マウント残骸を掃除
    local m
    for m in ${(f)"$(mount | awk '/@.* on .* \(nfs/ {for (i=1;i<=NF;i++) if ($i=="on") print $(i+1)}')"}; do
        diskutil unmount force "$m" 2>/dev/null
    done
}

### Completions ###
# zshrc は compinit → .zsh/*.zsh の順で読むので、ここで compdef 可能

# ~/.ssh/config を Include 再帰展開して Host エントリを収集
# (ssh_config(5): Include の相対パスは ~/.ssh/ 起点、glob 可、再帰的に処理)
_sshmount_collect_hosts() {
    local -a queue results includes
    queue=("$HOME/.ssh/config")
    local cfg p
    while (( ${#queue} )); do
        cfg=${queue[1]}
        queue=(${queue[2,-1]})
        [[ -r "$cfg" ]] || continue
        includes=( ${(f)"$(awk 'tolower($1)=="include" {for (i=2; i<=NF; i++) print $i}' "$cfg" 2>/dev/null)"} )
        for p in $includes; do
            p="${p/#\~/$HOME}"
            [[ "$p" = /* ]] || p="$HOME/.ssh/$p"
            queue+=(${~p}(N))
        done
        results+=( ${(f)"$(awk 'tolower($1)=="host" {for (i=2; i<=NF; i++) if ($i !~ /[*?!]/) print $i}' "$cfg" 2>/dev/null)"} )
    done
    print -l -- ${(u)results}
}

_sshmount() {
    if (( CURRENT == 2 )); then
        # scp 流儀: "host:" までを消費できたらリモートパス補完、
        # そうでなければホスト補完 (末尾 : は _describe の -S で付与)
        if compset -P '*:'; then
            _remote_files -/ -- ssh
        else
            local -a hosts
            hosts=( ${(f)"$(_sshmount_collect_hosts)"} )
            _describe -t hosts 'ssh host' hosts -S ':'
        fi
    elif (( CURRENT == 3 )); then
        _path_files -/
    fi
}
compdef _sshmount sshmount

_sshumount() {
    # -f / --force を skip して mount point 補完に集中する
    local -a args
    args=( "${words[@]:1}" )
    local -a mounts
    mounts=( ${(f)"$(mount | awk '/@.* on .* \(nfs/ || /fuse.?t/ || /osxfuse/ || /macfuse/ {
        for (i=1; i<=NF; i++) if ($i == "on") { print $(i+1); break }
    }')"} )
    _arguments \
        '(-f --force)'{-f,--force}'[force unmount: kill sshfs pids + diskutil unmount force]' \
        '*:mounted point:->mp'
    case $state in
        mp)
            _describe -t mounts 'mounted point' mounts
            _path_files -/
            ;;
    esac
}
compdef _sshumount sshumount

_sshmount_kill() {
    local -a mounts
    mounts=( ${(f)"$(mount | awk '/@.* on .* \(nfs/ || /fuse.?t/ || /osxfuse/ || /macfuse/ {
        for (i=1; i<=NF; i++) if ($i == "on") { print $(i+1); break }
    }')"} )
    _describe -t mounts 'mounted point (optional)' mounts
    _path_files -/
}
compdef _sshmount_kill sshmount-kill
