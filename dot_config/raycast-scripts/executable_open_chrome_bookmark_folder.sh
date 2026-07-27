#!/opt/homebrew/bin/bash

# 参考：https://github.com/RyuseiNomi/bookmark_fzf/blob/master/bookmark_fzf
# ブックマークバーにある指定のフォルダ内のURLを一括展開する
# usage:
# ./open_chrome_bookmark_folder.sh "work"

declare -A datas
names=()

function convert_hash() {
  local len=$(echo $1 | jq length)
  local COUNT=0
  while [ $COUNT -lt $len ]; do
    local row_data=$(echo $1 | jq .[$COUNT])
    local name=$(echo $row_data | jq .name)
    local url=$(echo $row_data | jq .url)
    datas[$name]=$url
    names+=("$name") # shellのhashは順不同なので、配列で順番を保持する
    ((COUNT++))
  done
}

function open_bookmark_folder() {
  data=$(cat ~/Library/Application\ Support/Google/Chrome/Default/Bookmarks)
  local len=$(echo $data | jq .roots.bookmark_bar.children | jq length)
  bookmark_list=$(echo $data | jq .roots.bookmark_bar.children)
  ROW_COUNT=0
  while [ $ROW_COUNT -lt $len ]; do
    row_data=$(echo $bookmark_list | jq .[$ROW_COUNT])
    type=$(echo $row_data | jq .type)
    name=$(echo $row_data | jq .name)
    if [ $type != "\"folder\"" -o $name != "\"$1\"" ]; then
      ((ROW_COUNT++))
      continue
    fi

    convert_hash "$(echo $row_data | jq .children)"
    break
  done

  for name in "${names[@]}"; do
    local url=${datas[$name]//\"/}
    echo "$name : $url"
    open $url
  done
}

open_bookmark_folder $1
