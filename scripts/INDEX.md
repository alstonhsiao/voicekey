# scripts — Utility Scripts Index

> 開發與驗證用腳本。執行前確認 `env.local` 已設定且未 commit。

| Script | Purpose |
|---|---|
| `test_api_key.py` | 驗證 OpenAI API 連線（`/v1/models`，免費 smoke test） |
| `test_cerebras.py` | 驗證 Cerebras API 連線（一次小型 chat completion，消耗少量 token） |
