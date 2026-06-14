"""臨時測試腳本（plan20260614.md §4.5）— 驗證 _voice_vocab.apply()。

三案例：
  王之名 → 王志明（拼音命中）
  王之明 → 王志明（拼音命中）
  王大明 → 不變（拼音不同，不誤改）
外加：overrides 家模 → 加模。

執行：approach-6-whisper-macos/.venv/bin/python scripts/test_vocab.py
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

# 讓 import 找得到 approach-6 模組
APP_DIR = Path(__file__).resolve().parent.parent / "approach-6-whisper-macos"
sys.path.insert(0, str(APP_DIR))

from _voice_vocab import VocabStore  # noqa: E402


def _make_store() -> VocabStore:
    vocab = {
        "people": ["王志明"],
        "companies": ["加模"],
        "projects": [],
        "terms": ["n8n"],
        "overrides": {"_comment": "x", "家模": "加模"},
    }
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False, encoding="utf-8"
    )
    json.dump(vocab, tmp, ensure_ascii=False)
    tmp.close()
    match_cfg = {
        "use_tone": False,
        "require_surname_char_same": False,
        "min_term_len": 2,
    }
    return VocabStore(Path(tmp.name), match_cfg)


def main() -> int:
    store = _make_store()

    cases = [
        # (輸入, 期望輸出, 說明)
        ("王之名", "王志明", "拼音命中：之名→志明"),
        ("王之明", "王志明", "拼音命中：之明→志明"),
        ("王大明", "王大明", "拼音不同，不誤改"),
        ("今天和王之名開會", "今天和王志明開會", "句中嵌入命中"),
        ("這是家模公司", "這是加模公司", "overrides 字面替換"),
        ("王志明", "王志明", "已正確不重複改"),
    ]

    all_pass = True
    print(f"stt_keyterms = {store.stt_keyterms}")
    print("-" * 50)
    for src, expect, desc in cases:
        out = store.apply(src)
        ok = out == expect
        all_pass = all_pass and ok
        mark = "✅" if ok else "❌"
        print(f"{mark} {src!r} → {out!r}  (期望 {expect!r})  [{desc}]")

    print("-" * 50)
    if all_pass:
        print("✅ 全部通過")
        return 0
    print("❌ 有案例未通過")
    return 1


if __name__ == "__main__":
    sys.exit(main())
