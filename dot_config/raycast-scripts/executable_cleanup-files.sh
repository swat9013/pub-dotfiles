#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Cleanup Files
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🧹
# @raycast.description Desktop/Downloadの整理、Docker prune、開発キャッシュ削除、ゴミ箱削除
# @raycast.needsConfirmation true

export PATH="/opt/homebrew/bin:$PATH"

# --- 関数定義 ---

list_files_with_highlight() {
  local dir="$1"
  local threshold=$((14 * 86400))
  local now
  now=$(date +%s)
  local count=0

  echo "=== ${dir} ==="

  while IFS= read -r -d '' file; do
    local mtime name age_days
    mtime=$(stat -f '%m' "$file")
    name=$(basename "$file")
    age_days=$(( (now - mtime) / 86400 ))
    count=$((count + 1))

    if (( (now - mtime) <= threshold )); then
      printf "  \033[32m★ %-40s (%d日前)\033[0m\n" "$name" "$age_days"
    else
      printf "    %-40s (%d日前)\n" "$name" "$age_days"
    fi
  done < <(find "$dir" -maxdepth 1 -not -name '.*' -not -path "$dir" -print0 | sort -z)

  if (( count == 0 )); then
    echo "  (空)"
  else
    echo "  合計: ${count}件"
  fi
  echo ""
}

confirm_dialog() {
  local message="$1"
  osascript <<OSASCRIPT &>/dev/null || return 1
display dialog "$message" buttons {"Cancel", "OK"} default button "Cancel"
OSASCRIPT
  return 0
}

cleanup_dir() {
  local dir="$1"
  if find "$dir" -maxdepth 1 -not -name '.*' -not -path "$dir" -print0 | xargs -0 rm -rf; then
    echo "  ${dir} を削除しました"
  else
    echo "  ERROR: ${dir} の削除に失敗しました"
  fi
}

# --- ステージ1: ファイル確認＋削除 ---

echo "=========================================="
echo "  ステージ1: Desktop/Download 整理"
echo "=========================================="
echo ""

list_files_with_highlight "${HOME}/Desktop"
list_files_with_highlight "${HOME}/Downloads"

if confirm_dialog "Desktop/Downloadの全ファイル・フォルダを削除しますか？"; then
  cleanup_dir "${HOME}/Desktop"
  cleanup_dir "${HOME}/Downloads"
else
  echo "  SKIP: ファイル削除をキャンセルしました"
fi

echo ""

# --- ステージ2: システムクリーン ---

echo "=========================================="
echo "  ステージ2: システムクリーン"
echo "=========================================="
echo ""

# Google Drive
echo "=== Google Drive ==="
open "https://drive.google.com/drive/my-drive"
echo "  Google Driveをブラウザで開きました"
echo ""

# Docker prune
echo "=== Docker system prune ==="
if command -v docker &>/dev/null; then
  if docker system prune --volumes -f 2>&1; then
    echo "  Docker prune 完了"
  else
    echo "  ERROR: Docker pruneに失敗しました（Daemon未起動の可能性）"
  fi
else
  echo "  SKIP: docker not found"
fi
echo ""

# 開発キャッシュ（いずれも再取得できる）
echo "=== 開発キャッシュ ==="
if confirm_dialog "開発キャッシュ（uv の古い環境 / npm / Homebrew / アプリ更新用）を削除しますか？"; then
  # uv cache clean は動作中の uv プロセスを待つため、7 日以上前の環境だけを直接消す。
  # main-* は常駐する MCP server の環境なので残す。
  find "${HOME}/.cache/uv/environments-v2" -mindepth 1 -maxdepth 1 -mtime +7 -not -name 'main-*' -exec rm -rf {} +
  echo "  uv の古い環境を削除しました"
  for cmd in "npm cache clean --force" "brew cleanup -s"; do
    if ! command -v "${cmd%% *}" &>/dev/null; then
      echo "  SKIP: ${cmd%% *} not found"
    elif $cmd 2>&1; then
      echo "  ${cmd} 完了"
    else
      echo "  ERROR: ${cmd} に失敗しました"
    fi
  done
  rm -rf "${HOME}/Library/Caches/rancher-desktop-updater" "${HOME}/Library/Caches/com.microsoft.VSCode.ShipIt"
  echo "  アプリ更新用キャッシュを削除しました"
else
  echo "  SKIP: 開発キャッシュの削除をキャンセルしました"
fi
echo ""

# ゴミ箱
echo "=== ゴミ箱 ==="
if confirm_dialog "ゴミ箱を空にしますか？"; then
  osascript -e 'tell application "Finder" to empty trash'
  echo "  ゴミ箱を空にしました"
else
  echo "  SKIP: ゴミ箱の削除をキャンセルしました"
fi

echo ""
echo "=========================================="
echo "  クリーンアップ完了"
echo "=========================================="
