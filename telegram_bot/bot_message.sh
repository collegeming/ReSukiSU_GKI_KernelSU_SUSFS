#!/bin/bash
# 远程 curl 调用发 TG 消息，无交互、无硬编码 token

# 用法：
# curl -sL https://raw.githubusercontent.com/xxx/xxx/bot_message.sh | bash -s "BOT_TOKEN" "CHAT_ID" "THREAD_ID" "消息内容"

BOT_TOKEN="$1"
CHAT_ID="$2"
MESSAGE_THREAD_ID="$3"
TEXT="$4"

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] || [ -z "$TEXT" ]; then
  echo "用法："
  echo "curl -sL https://xxx.sh | bash -s \"BOT_TOKEN\" \"CHAT_ID\" \"THREAD_ID\" \"消息\""
  exit 1
fi

if [ -z "$MESSAGE_THREAD_ID" ]; then
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${TEXT}"
else
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d message_thread_id="${MESSAGE_THREAD_ID}" \
    -d text="${TEXT}"
fi

echo -e "\n✅ 消息发送完成"