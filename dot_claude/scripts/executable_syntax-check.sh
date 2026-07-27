#!/bin/sh
# bash/sh/zsh script の構文チェック wrapper。
# `syntax-check.sh <shell> <file>` で `<shell> -n <file>` 相当を実行する。
# settings.deny が Bash(bash|sh|zsh:*) を塞いだままでも構文チェックだけを通すために、
# 本 script を permissions.allow に個別登録して使う。
# 第1引数を bash/sh/zsh に限定し、許可済み wrapper が任意バイナリ実行の踏み台になるのを防ぐ。
set -eu

shell=${1:-}
file=${2:-}

case "$shell" in
  bash | sh | zsh) ;;
  *)
    printf 'syntax-check: unsupported shell: %s\n' "$shell" >&2
    exit 2
    ;;
esac

if [ -z "$file" ]; then
  printf 'syntax-check: missing file argument\n' >&2
  exit 2
fi

# -n は parse only (実行しない)。file は単一引数として渡り shell 展開されない。
exec "$shell" -n "$file"
