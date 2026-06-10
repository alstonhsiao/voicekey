import os
from pathlib import Path
import requests

def load_env_local():
    """從 env.local / .env.local 讀取環境變數"""
    env_paths = [
        Path(__file__).parent / "env.local",
        Path(__file__).parent / ".env.local",
        Path(__file__).parent.parent / "env.local",
        Path(__file__).parent.parent / ".env.local",
    ]
    for env_path in env_paths:
        if env_path.exists():
            with open(env_path, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, _, value = line.partition("=")
                        os.environ.setdefault(key.strip(), value.strip())
            print(f"✅ 已讀取環境檔：{env_path}")
            return
    print("⚠️  找不到 env.local / .env.local，嘗試使用系統環境變數")

def test_cerebras():
    load_env_local()
    api_key = os.environ.get("CEREBRAS_API_KEY", "")

    if not api_key or api_key == "your_cerebras_key_here":
        print("❌ 找不到 CEREBRAS_API_KEY，請確認 env.local 已設定並填寫正確")
        return False

    print(f"✅ 找到 API Key（前綴：{api_key[:8]}...，長度：{len(api_key)} 字元）")
    print("🔄 正在連線到 Cerebras API...")

    url = "https://api.cerebras.ai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    data = {
        "model": "gpt-oss-120b",
        "messages": [
            {"role": "user", "content": "回覆：OK"}
        ],
        "max_tokens": 100,
        "temperature": 0.0
    }

    try:
        response = requests.post(url, headers=headers, json=data, timeout=10)
    except Exception as e:
        print(f"❌ 連線失敗: {e}")
        return False

    if response.status_code == 200:
        try:
            content = response.json()["choices"][0]["message"]["content"].strip()
            print(f"✅ Cerebras 連線測試成功！回傳內容：{content}")
            return True
        except Exception as e:
            print(f"⚠️ 解析回傳內容失敗，但 HTTP 狀態碼為 200: {e}")
            return False
    else:
        print(f"❌ API 呼叫失敗，HTTP 狀態碼：{response.status_code}")
        print(f"回應：{response.text}")
        return False

if __name__ == "__main__":
    test_cerebras()
