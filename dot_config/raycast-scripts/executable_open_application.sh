#!/bin/bash

if [ $# != 1 ]; then
    echo 引数エラー: $*
    exit 1
fi

command=$1
# 実行中のコマンドをチェックする
if ps -ef | grep -v grep | grep -v "$0" | grep "${command}" > /dev/null
then
    open "${command}"
else
    echo "Command is not running"
fi
