# path-prepend.sh (→ ~/.config/shell/path-prepend.sh): PATH 前置の共有 primitive。
# path_prepend <dir>... を定義するのみ (dir list は消費側が所有)。source して使う。
#
# guard-skip (PATH に在れば skip) にせず常に先頭へ動かす (remove-then-prepend) のは、
# skip だと /etc/zprofile の path_helper が /opt/homebrew/bin を後ろへ回した順序を復旧できず、
# git が Apple Git に解決される回帰 (issue #68 系) が再発するため。位置まで含めて冪等。
#
# 検証: scripts/test-path-prepend.sh
path_prepend() {
	local dir
	for dir in "$@"; do
		[ -d "$dir" ] || continue
		# 除去パターンは "" で囲み literal 化する (dir 内 glob metachar による誤除去を防ぎ、
		# bash/zsh の挙動を一致させる)。
		PATH=":${PATH}:"
		PATH="${PATH//":${dir}:"/:}"
		PATH="${PATH#:}"
		PATH="${PATH%:}"
		PATH="${dir}${PATH:+:${PATH}}"
	done
}
