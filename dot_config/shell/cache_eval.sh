# cache_eval.sh (→ ~/.config/shell/cache_eval.sh): 起動時に `eval "$(tool init)"` していた
# shell code を file cache 経由で source する共有 primitive。
# cache_eval を定義するのみ (何を cache するかは消費側が所有)。source して使う。
#
#   cache_eval <name> [-d <dep>]... <cmd> [arg]...
#
# <cmd> の stdout を shell code とみなし ${XDG_CACHE_HOME:-~/.cache}/shell-eval/<name>.sh
# へ保存して source する。cache が有効なら <cmd> の fork ごと消える。
#
# 無効化条件は「生成元 binary の mtime」と「その binary が入っている dir の mtime」。
# dir も見るのは Homebrew のような symlink farm 対策: bin/<cmd> は Cellar への symlink で、
# test -nt は symlink を辿るため mtime が bottle のビルド時刻になり upgrade でも進まない
# ことがある。unlink→link は bin dir の mtime を必ず進めるのでそちらで捕まえる。
# 代償は無関係な brew install 後の 1 回だけ全 cache が再生成されること — 手動削除が要る
# stale cache より、余分な再生成 1 回を選ぶ。
#
# -d は binary 以外の無効化条件を足す (sheldon の plugins.toml のような設定 file)。
# name は cache file 名になるため `/` を含められない。
#
# 生成物の検証は「exit status が 0」「stdout が非空」の 2 点まで。shell 文法の妥当性までは
# 見ない (portable に検証できない)。exit 0 で壊れた code を出す tool は上流のバグで、
# source 時に毎起動 error が出る形になる — 無音にはならないのでそこで止める。
#
# 生成元を絶対 path の実行可能 file に解決できない場合は何も source せず 1 を返す。
# mtime を取れない対象 (shell function / builtin) を cache すると無効化が永久に成立せず
# stale が固定化するため、暗黙に fallback せず失敗させる。呼び出し側は従来どおり
# `command -v <cmd>` で存在を gate する。
#
# local 変数を _cache_eval_ で前置するのは、最後の `. "$cache"` が関数内 source になり、
# cache 側 (tool が生成した init code) の代入が同名 local を掴んでしまうのを避けるため。
# name / cache / bin のような素の名前だと現実的に衝突しうる。
#
# 関数内 source では $@ と $funcstack も cache_eval のものになる。clap 系の completion は
# top-level で `[ "$funcstack[1]" = _foo ]` を見て自己実行と compdef 登録を切り替えるが、
# 適用先 (herdr / wt / wtp) では compdef 側に落ちて _comps への登録が成立することを実機で
# 確認済み。新しい適用先を足すときは compdef / 関数定義が生きているかを確かめる。

# 生成元 binary を PATH 上で解決し _cache_eval_bin へ入れる。呼び出し側の local に
# 動的スコープで書き戻すため、値は stdout ではなく変数で返す —
# `$(command -v ...)` は subshell fork になり、呼び出し 1 件ごとに数 ms を起動 hot path へ
# 戻してしまう (cache 化で消したはずの fork が resolve 側で復活する)。
# PATH の走査は word splitting を使わず parameter expansion だけで回す。zsh は既定で
# $PATH を分割しないため、`for dir in $PATH` は sh / bash と挙動が揃わない。
_cache_eval_resolve() {
	local _cache_eval_rest _cache_eval_dir
	case "$1" in
	*/*)
		_cache_eval_bin="$1"
		return 0
		;;
	esac
	_cache_eval_bin=''
	# 末尾に : を足すことで、非空の間は必ず区切りが 1 個以上残る (無限 loop の防止)。
	_cache_eval_rest="${PATH}:"
	while [ -n "$_cache_eval_rest" ]; do
		_cache_eval_dir="${_cache_eval_rest%%:*}"
		_cache_eval_rest="${_cache_eval_rest#*:}"
		: "${_cache_eval_dir:=.}"
		if [ -f "${_cache_eval_dir}/$1" ] && [ -x "${_cache_eval_dir}/$1" ]; then
			_cache_eval_bin="${_cache_eval_dir}/$1"
			return 0
		fi
	done
	return 1
}

cache_eval() {
	local _cache_eval_cache _cache_eval_dep_stale _cache_eval_bin _cache_eval_tmp
	[ "$#" -ge 2 ] || return 2
	case "$1" in
	*/* | '') return 2 ;;
	esac
	_cache_eval_cache="${XDG_CACHE_HOME:-$HOME/.cache}/shell-eval/${1}.sh"
	shift

	_cache_eval_dep_stale=''
	while [ "${1-}" = '-d' ]; do
		[ "$#" -ge 3 ] || return 2
		if [ "$2" -nt "$_cache_eval_cache" ]; then
			_cache_eval_dep_stale=1
		fi
		shift 2
	done

	_cache_eval_resolve "$1" || return 1
	case "$_cache_eval_bin" in
	/*) [ -f "$_cache_eval_bin" ] && [ -x "$_cache_eval_bin" ] || return 1 ;;
	*) return 1 ;;
	esac

	# 生成は解決済み binary で行う。`"$@"` だと同名の shell function が優先され、mtime を
	# 見た対象と実際の生成元が食い違う (対象 tool は自分の init 出力で同名 function を定義する
	# ため、cache が stale な状態で .zshrc を再 source すると発火する)。
	shift

	if [ ! -r "$_cache_eval_cache" ] ||
		[ -n "$_cache_eval_dep_stale" ] ||
		[ "$_cache_eval_bin" -nt "$_cache_eval_cache" ] ||
		[ "${_cache_eval_bin%/*}" -nt "$_cache_eval_cache" ]; then
		mkdir -p "${_cache_eval_cache%/*}" || return 1
		# 生成が途中で失敗しても壊れた cache を source しないよう tmp 経由で入れ替える。
		# exit 0 でも stdout が空なら失敗扱いにする — 空 cache は mtime 判定を通り続けるので、
		# 一過性の空出力が永久に凍結し prompt や補完が無音で消える (手動削除が要る状態の再発)。
		_cache_eval_tmp="${_cache_eval_cache}.$$"
		if ! "$_cache_eval_bin" "$@" >"$_cache_eval_tmp" || [ ! -s "$_cache_eval_tmp" ]; then
			rm -f "$_cache_eval_tmp"
			return 1
		fi
		mv -f "$_cache_eval_tmp" "$_cache_eval_cache" || {
			rm -f "$_cache_eval_tmp"
			return 1
		}
	fi

	. "$_cache_eval_cache"
}
