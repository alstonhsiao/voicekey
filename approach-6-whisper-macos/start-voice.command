#!/bin/bash
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$APP_DIR/.venv/bin/python"
PID_FILE="$HOME/Library/Application Support/WhisperVoice/WhisperVoice.pid"

# 清除可能殘留的舊 PID 檔（進程已不存在）
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ! kill -0 "$OLD_PID" 2>/dev/null; then
        rm -f "$PID_FILE"
    fi
fi

if [ ! -f "$PYTHON" ]; then
    echo "❌ 找不到虛擬環境，請先執行 install.sh"
    exit 1
fi

echo "🎤 啟動語音轉文字工具..."
osascript -e 'tell application "Terminal" to activate' >/dev/null 2>&1
cd "$APP_DIR"
"$PYTHON" main.py
