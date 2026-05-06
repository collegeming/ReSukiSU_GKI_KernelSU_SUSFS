#!/bin/bash
# ===== Telegram 消息发送工具 =====
echo "=== Telegram 消息发送工具 ==="
read -p "请输入 Bot Token: " BOT_TOKEN
read -p "请输入目标 Chat ID: " CHAT_ID
read -p "请输入话题 Thread ID (没有则留空回车): " MESSAGE_THREAD_ID
read -p "请输入要发送的消息内容: " TEXT

# ===== 发送请求 =====
if [ -z "$MESSAGE_THREAD_ID" ]; then
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
         -d chat_id="${CHAT_ID}" \
         -d text="${TEXT}")
else
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
         -d chat_id="${CHAT_ID}" \
         -d message_thread_id="${MESSAGE_THREAD_ID}" \
         -d text="${TEXT}")
fi

# ===== 结果反馈 =====
echo -e "\n发送结果:"
echo "$RESPONSE" | grep -q "\"ok\":true" && echo "✅ 消息发送成功！" || echo "❌ 发送失败，请检查参数或网络。"