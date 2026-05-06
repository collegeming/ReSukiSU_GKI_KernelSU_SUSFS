#!/bin/bash
# Telegram Send Message - 优化极简调用版
set -euo pipefail

echo "=== Telegram 消息发送工具 ==="

# 定义参数
BOT_TOKEN=""
CHAT_ID=""
THREAD_ID=""
TEXT=""

# 智能适配参数个数，简化本地调用
case $# in
    3)
        # 用法1：不带话题线程 ID
        BOT_TOKEN="$1"
        CHAT_ID="$2"
        TEXT="$3"
        ;;
    4)
        # 用法2：带话题线程 ID
        BOT_TOKEN="$1"
        CHAT_ID="$2"
        THREAD_ID="$3"
        TEXT="$4"
        ;;
    *)
        echo "用法1（无话题）: bash tg-send.sh BOT_TOKEN CHAT_ID 消息内容"
        echo "用法2（有话题）: bash tg-send.sh BOT_TOKEN CHAT_ID THREAD_ID 消息内容"
        echo "远程调用: curl -sL 脚本地址 | bash -s BOT_TOKEN CHAT_ID [THREAD_ID] 消息内容"
        exit 1
        ;;
esac

# 必传参数校验
if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" || -z "$TEXT" ]]; then
    echo "❌ 缺少必要参数"
    exit 1
fi

# 构造请求并发送
API_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
CURL_ARGS=(-s -X POST "$API_URL" -d "chat_id=${CHAT_ID}" -d "text=${TEXT}")

# 有话题 ID 追加参数
if [[ -n "$THREAD_ID" ]]; then
    CURL_ARGS+=(-d "message_thread_id=${THREAD_ID}")
fi

RESPONSE=$(curl "${CURL_ARGS[@]}")

# 结果判断
if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo "✅ 发送成功"
else
    echo "❌ 发送失败"
    echo "响应内容: $RESPONSE"
    exit 1
fi