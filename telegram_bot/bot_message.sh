#!/bin/bash
# 极简调用：curl -sL 脚本地址 | bash -s <token> <chat_id> [thread_id] <msg>

[ $# -lt 3 ] && {
  echo "用法：curl -sL 脚本地址 | bash -s 机器人令牌 聊天ID 消息内容"
  echo "用法：curl -sL 脚本地址 | bash -s 机器人令牌 聊天ID 话题ID 消息内容"
  exit 1
}

export BOT_TOKEN="$1"
export CHAT_ID="$2"

if [ $# -eq 3 ]; then
  export TEXT="$3"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$TEXT" > /dev/null
elif [ $# -ge 4 ]; then
  export THREAD_ID="$3"
  export TEXT="${@:4}"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d message_thread_id="$THREAD_ID" \
    -d text="$TEXT" > /dev/null
fi

echo "✅ 消息已发送"