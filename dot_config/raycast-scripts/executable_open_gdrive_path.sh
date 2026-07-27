#!/opt/homebrew/bin/bash

export PATH="/opt/homebrew/bin:$PATH"

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Google Drive Path
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 📂
# @raycast.argument1 { "type": "text", "placeholder": "G:\\共有ドライブ\\..." }

set -euo pipefail

# Raycastの入力欄が長いパスを折り返す際に空白が混入するため除去
WIN_PATH=$(echo "$1" | tr -d ' \t\n\r' | nkf -w --ic=utf8-mac)

# ---- パス検証 ----
if [[ "$WIN_PATH" != *'共有ドライブ'* ]]; then
  echo "❌ 共有ドライブパスではありません"
  exit 1
fi

# ---- パス解析 ----
# "共有ドライブ\" 以降を取り出し、"\" で分割
trimmed="${WIN_PATH#*共有ドライブ\\}"
IFS='\' read -ra SEGMENTS <<< "$trimmed"

if [[ ${#SEGMENTS[@]} -lt 2 ]]; then
  echo "❌ パスが短すぎます（共有ドライブ名+サブフォルダが必要）"
  exit 1
fi

# segment[0] = 共有ドライブ名（スキップ）
# segment[1] = 最初のサブフォルダ（検索起点）
# segment[2..] = 以降のフォルダ/ファイル

FIRST_FOLDER="${SEGMENTS[1]}"
REMAINING=("${SEGMENTS[@]:2}")

# ---- Step 1: 最初のサブフォルダを検索 ----
RESULT=$(gog drive search --raw-query "name='${FIRST_FOLDER}' and mimeType='application/vnd.google-apps.folder'" --json --results-only 2>/dev/null)
CURRENT_ID=$(echo "$RESULT" | jq -r '.[0].id // empty')

if [[ -z "$CURRENT_ID" ]]; then
  echo "❌ フォルダが見つかりません: $FIRST_FOLDER"
  exit 1
fi

# ---- Step 2: 残りのセグメントを階層で辿る ----
for i in "${!REMAINING[@]}"; do
  SEG="${REMAINING[$i]}"
  IS_LAST=$(( i == ${#REMAINING[@]} - 1 ))

  if [[ $IS_LAST -eq 1 ]]; then
    # 最終セグメントはファイルの可能性もあるためmimeType制約なし
    QUERY="name='${SEG}'"
  else
    QUERY="name='${SEG}' and mimeType='application/vnd.google-apps.folder'"
  fi

  RESULT=$(gog drive ls --parent "$CURRENT_ID" --query "$QUERY" --json --results-only 2>/dev/null)
  NEXT_ID=$(echo "$RESULT" | jq -r '.[0].id // empty')

  if [[ -z "$NEXT_ID" ]]; then
    echo "❌ 見つかりません: $SEG"
    exit 1
  fi

  CURRENT_ID="$NEXT_ID"
done

# ---- Step 3: ブラウザで開く ----
RESULT=$(gog drive get "$CURRENT_ID" --json 2>/dev/null)
URL=$(echo "$RESULT" | jq -r '.file.webViewLink // empty')

if [[ -z "$URL" ]]; then
  URL="https://drive.google.com/drive/folders/$CURRENT_ID"
fi

open "$URL"
echo "✅ 開きました"
