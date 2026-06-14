#!/bin/bash
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$APP_DIR/.venv/bin/python"
PID_FILE="$HOME/Library/Application Support/WhisperVoice/WhisperVoice.pid"

echo "🔄 重啟語音轉文字工具..."

# 從 PID 檔找到並結束現有程序（比對 main.py 防止誤殺）
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        if ps -p "$OLD_PID" -o command= 2>/dev/null | grep -q "main.py"; then
            echo "🛑 結束現有程序 (PID: $OLD_PID)..."
            kill "$OLD_PID"
            sleep 1
        else
            echo "⚠️  PID $OLD_PID 不是本程式，略過"
        fi
    fi
    rm -f "$PID_FILE"
fi

if [ ! -f "$PYTHON" ]; then
    echo "❌ 找不到虛擬環境，請先執行 install.sh"
    exit 1
fi

echo "🎤 啟動語音轉文字工具..."
cd "$APP_DIR"
"$PYTHON" main.py
