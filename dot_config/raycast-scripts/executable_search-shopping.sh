#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Search Shopping
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🛍️
# @raycast.argument1 { "type": "text", "placeholder": "Keyword" }

argv=("$@")
keyword=""

convert_utf8(){
  echo $(echo "$1" | nkf -w --ic=utf8-mac)
  return 0
}

for i in `seq 1 $#`
do
  if [ $i = "1" ] ; then
    keyword=$(convert_utf8 "${argv[$i-1]}")
  else
  tmp=$(convert_utf8 "${argv[$i-1]}")
  keyword="${keyword}+${tmp}"
  fi
done

open "https://search.rakuten.co.jp/search/mall/${keyword}"
open "https://www.yodobashi.com/?word=${keyword}"
open "https://www.amazon.co.jp/s?k=${keyword}"
open "https://jp.mercari.com/search?keyword=${keyword}"

echo "open search result by 「 ${keyword}」"
exit
