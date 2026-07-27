# mise（キャッシュ方式。miseアップデート時は手動でキャッシュ削除）
_mise_cache="${XDG_CACHE_HOME:-$HOME/.cache}/mise/activate.zsh"
if [[ ! -r "$_mise_cache" ]] && command -v mise >/dev/null 2>&1; then
    mkdir -p "${_mise_cache:h}"
    mise activate zsh > "$_mise_cache"
fi
[[ -r "$_mise_cache" ]] && source "$_mise_cache"
unset _mise_cache
