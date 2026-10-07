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
  # コマンドの成否をそのまま返すので、後続ステップの実行可否を呼び出し側で分岐できる。
  local name="$1"
  shift
  echo "=== ${name} ==="
  if "$@"; then
    return 0
  fi
  errors+=("${name}")
  return 1
}

# --- 更新群 ---

# trust の正本は Brewfile の `trusted: true` 宣言 (ADR 0019 §3、Homebrew 6.0+)。
# install / cleanup とも entry 読込前に宣言を trust store へ適用するため、
# 事前の brew trust step (brew-trust-taps.sh) は廃止した。
#
# install と cleanup は別ステップとして報告する。--force-cleanup で一括実行すると
# unlisted の uninstall・trust store の書き換え・末尾の `brew cleanup` の失敗が
# すべて "brew bundle" 名義になり、install 本体が成功していても
# 「brew bundle が失敗」と通知される (実測で untrusted tap / uninstall 拒否 /
# tap clone 破損 / cleanup の非ゼロ終了の 4 種が同じ名前で報告されてきた)。
#
# なお cleanup は末尾で無条件に `brew cleanup` を呼ぶ (抑止 flag は無い)。後段の
# "brew cleanup" ステップと重複するうえ、Homebrew 側が stderr を捨てるためここでの
# 失敗は原因不明のまま非ゼロで返る。ステップ名を分けて切り分け可能にする。
#
# install 失敗時に cleanup を走らせないのは --force-cleanup と同じ順序 (install が
# 非ゼロなら Homebrew は cleanup へ進まない) を保つため。
if run_step "brew bundle" brew bundle install --global; then
  run_step "brew bundle cleanup" brew bundle cleanup --global --force
else
  echo "SKIP: brew bundle install が失敗したため cleanup をスキップ"
fi

echo "=== uv tool upgrade ==="
if command -v uv &>/dev/null; then
  if ! uv tool upgrade --all; then
    errors+=("uv tool upgrade")
  fi
else
  echo "SKIP: uv command not found"
fi

# mise は runtime (言語処理系) の版管理専任 (ADR 0019)。宣言追加を反映する install →
# 導入済みの更新 (plugin update / upgrade) の順で流す。
echo "=== mise install ==="
if command -v mise &>/dev/null; then
  if ! mise install --yes; then
    errors+=("mise install")
  fi
else
  echo "SKIP: mise command not found"
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
