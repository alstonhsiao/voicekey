# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.31.0",
# ]
# ///

"""
OpenAI API Key 測試腳本

使用方式：
  uv run test_api_key.py

說明：
  呼叫 GET /v1/models 端點（免費，不消耗任何 token 或 Whisper 額度）
  只用來驗證 API Key 格式正確且帳號有效。
"""

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


def test_api_key():
    load_env_local()

    api_key = os.environ.get("OPENAI_API_KEY", "")

    # 1. 格式檢查
    if not api_key:
        print("❌ 找不到 OPENAI_API_KEY，請確認 env.local / .env.local 已設定")
        return False

    if not api_key.startswith("sk-"):
        print(f"❌ API Key 格式不正確（應以 sk- 開頭）")
        return False

    print(f"✅ API Key 格式正確（前綴：sk-***，長度：{len(api_key)} 字元）")

    # 2. 呼叫 GET /v1/models（免費端點，只驗證 Key 有效性）
    print("\n🔄 正在連線到 OpenAI API...")
    try:
        response = requests.get(
            "https://api.openai.com/v1/models",
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=15,
        )
    except requests.exceptions.ConnectionError:
        print("❌ 無法連線 OpenAI API，請檢查網路連線")
        return False
    except requests.exceptions.Timeout:
        print("❌ 連線逾時（>15 秒），請稍後再試")
        return False

    # 3. 解析結果
    if response.status_code == 200:
        models = response.json().get("data", [])
        whisper_available = any("whisper" in m.get("id", "") for m in models)

        print(f"✅ API Key 有效！帳號可存取 {len(models)} 個模型")

        if whisper_available:
            print("✅ Whisper 模型可用（whisper-1）— 語音辨識功能就緒")
        else:
            print("⚠️  帳號中找不到 Whisper 模型，請確認帳號有 Whisper API 存取權限")

        print("\n🎉 測試通過！可以開始使用語音轉文字功能")
        return True

    elif response.status_code == 401:
        print("❌ API Key 無效（HTTP 401 Unauthorized）")
        print("   請確認：")
        print("   1. env.local（或 .env.local）中的 Key 是完整複製，沒有多餘空格")
        print("   2. Key 已在 platform.openai.com/api-keys 啟用")
        print("   3. Key 沒有被撤銷")
        return False

    elif response.status_code == 429:
        print("⚠️  API 請求過於頻繁（HTTP 429），但 Key 本身應該是有效的")
        print("   請稍後再試")
        return False

    else:
        print(f"❌ 未預期的錯誤（HTTP {response.status_code}）")
        print(f"   回應內容：{response.text[:200]}")
        return False


if __name__ == "__main__":
    test_api_key()
