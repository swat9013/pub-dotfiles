#!/usr/bin/env bash
set -uo pipefail

# dotfiles が管理するパッケージ/ツールの更新と、開発キャッシュ削除を集約するスクリプト。
#
# 契約: 各ステップを実行し、失敗を errors 配列に集約して続行する。末尾で失敗
# ステップ名を出力し、1 件以上なら exit 1。通知・read 待機・GUI 依存は持たない
# (それらは呼び出し元の plugin-update.sh 側の責務)。
#
# Emacs straight パッケージ更新はスコープ外。pin の巻き戻りを避けるため、
# commit 確認付きの手動更新として運用する。

errors=()

run_step() {
  # $1: ステップ名 (失敗時の errors エントリ), $2..: 実行コマンド
  local name="$1"
  shift
  echo "=== ${name} ==="
  if ! "$@"; then
    errors+=("${name}")
  fi
}

# --- 更新群 ---

# brew bundle 直前に Brewfile 宣言の全 tap を trust する。Homebrew 6.0+ は
# HOMEBREW_REQUIRE_TAP_TRUST がデフォルト set のため、trust 未登録の third-party
# tap は formula 読込で拒否され brew bundle が失敗する。chezmoi 側の brew bundle は
# Brewfile の sha256 が変わるまで再実行されないので、trust.json が消えると
# routine update が永続的に失敗する。idempotent なため毎回実行しても安価。
echo "=== brew trust (Brewfile taps) ==="
if [[ -f "${HOME}/.Brewfile" ]]; then
  while read -r tap; do
    brew trust "${tap}" || echo "WARN: brew trust ${tap} failed (続行)"
  done < <(sed -nE 's/^[[:space:]]*tap "([^"]+)".*/\1/p' "${HOME}/.Brewfile")
else
  echo "SKIP: ~/.Brewfile not found"
fi

run_step "brew bundle" brew bundle install --global --force-cleanup

echo "=== uv tool upgrade ==="
if command -v uv &>/dev/null; then
  if ! uv tool upgrade --all; then
    errors+=("uv tool upgrade")
  fi
else
  echo "SKIP: uv command not found"
fi

echo "=== mise plugin update ==="
if command -v mise &>/dev/null; then
  if ! mise plugin update; then
    errors+=("mise plugin update")
  fi
else
  echo "SKIP: mise command not found"
fi

echo "=== mise upgrade ==="
if command -v mise &>/dev/null; then
  if ! mise upgrade; then
    errors+=("mise upgrade")
  fi
else
  echo "SKIP: mise command not found"
fi

echo "=== mas upgrade ==="
if ! command -v mas &>/dev/null; then
  echo "SKIP: mas command not found"
elif [[ ! -t 0 ]]; then
  # mas upgrade はアプリ更新時に sudo を呼ぶため tty が要る。launchd 等の
  # 非対話実行では sudo がパスワードを読めず失敗するのでスキップする
  # (docker daemon ガードと同じ「前提条件を満たさなければ SKIP」方針)。
  echo "SKIP: mas upgrade は対話的 sudo が必要（非対話実行のためスキップ）"
else
  if ! mas upgrade; then
    errors+=("mas upgrade")
  fi
fi

echo "=== sheldon lock --update ==="
if command -v sheldon &>/dev/null; then
  if ! sheldon lock --update; then
    errors+=("sheldon lock")
  fi
else
  echo "SKIP: sheldon command not found"
fi

# --- 開発キャッシュ削除群 ---

run_step "brew cleanup" brew cleanup --prune=all

echo "=== npm cache clean ==="
if command -v npm &>/dev/null; then
  if ! npm cache clean --force; then
    errors+=("npm cache clean")
  fi
else
  echo "SKIP: npm command not found"
fi

echo "=== pip cache purge ==="
if command -v pip &>/dev/null && pip --version &>/dev/null; then
  if ! pip cache purge; then
    errors+=("pip cache purge")
  fi
else
  echo "SKIP: pip not available"
fi

echo "=== Xcode DerivedData ==="
if [[ -d "${HOME}/Library/Developer/Xcode/DerivedData" ]]; then
  if ! rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/"*; then
    errors+=("xcode deriveddata")
  fi
else
  echo "SKIP: Xcode DerivedData not found"
fi

echo "=== docker builder prune ==="
if command -v docker &>/dev/null; then
  if docker info &>/dev/null; then
    if ! docker builder prune -f; then
      errors+=("docker builder prune")
    fi
  else
    echo "SKIP: Docker daemon not running"
  fi
else
  echo "SKIP: docker command not found"
fi

# --- 結果 ---
if [[ ${#errors[@]} -eq 0 ]]; then
  echo "dotfiles-update: all steps succeeded"
  exit 0
else
  failed=$(IFS=', '; echo "${errors[*]}")
  echo "dotfiles-update: failed steps: ${failed}" >&2
  exit 1
fi
