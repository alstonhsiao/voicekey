"""第三層後處理：使用者自訂詞彙的拼音 fuzzy 替換引擎。

設計重點（見 docs/archive/plan20260614.md §3.3）：
- 在 LLM 修正、OpenCC 繁化之後、貼上之前執行。
- 不呼叫任何 API、不耗 token、詞彙數量無上限。
- 對 people / companies / projects 用「無聲調全拼音 + 同字數」比對中文人名/公司名。
- terms（英文/數字術語）不進拼音引擎，僅供 STT keyterms 與字面比對。
- overrides 為字面強制替換，最高優先。
- 哲學：任何失敗一律降級、絕不拋例外（比照 Cerebras fallback）。
"""
from __future__ import annotations

import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

# pypinyin 為選配相依：缺套件時整層降級，不影響核心功能。
try:
    from pypinyin import Style, lazy_pinyin
    _PYPINYIN_OK = True
except Exception as e:  # pragma: no cover - 取決於安裝環境
    logger.warning("⚠️  pypinyin 未安裝，詞彙拼音比對停用（%s）", e)
    _PYPINYIN_OK = False


# CJK 統一表意文字範圍（含擴展 A），用來判定視窗是否為純中文。
def _is_cjk(ch: str) -> bool:
    return "㐀" <= ch <= "鿿"


def _all_cjk(s: str) -> bool:
    return bool(s) and all(_is_cjk(c) for c in s)


class VocabStore:
    """載入 user_vocab.json、建立拼音索引、提供 apply() 替換。"""

    # 進入拼音 fuzzy 比對的類別
    _PINYIN_CATEGORIES = ("people", "companies", "projects")
    # 進入 STT keyterms 的類別
    _KEYTERM_CATEGORIES = ("people", "companies", "projects", "terms")

    def __init__(self, path: Path, match_cfg: dict):
        self.path = Path(path)
        self.use_tone = bool(match_cfg.get("use_tone", False))
        self.require_surname_char_same = bool(match_cfg.get("require_surname_char_same", False))
        self.min_term_len = int(match_cfg.get("min_term_len", 2))
        self._style = Style.TONE3 if (self.use_tone and _PYPINYIN_OK) else (
            Style.NORMAL if _PYPINYIN_OK else None
        )

        self._mtime: float | None = None
        # (len, pinyin_tuple) -> canonical（拼音索引）
        self._pinyin_index: dict[tuple[int, tuple[str, ...]], str] = {}
        # 由大到小的詞長集合
        self._lengths: list[int] = []
        # 字面強制替換
        self._overrides: dict[str, str] = {}
        # 供 STT 使用的詞（已截斷）
        self._stt_keyterms: list[str] = []

        # 啟動即嘗試載入一次（檔案不存在也不報錯，等熱重載）
        self.maybe_reload(force=True)

    # ------------------------------------------------------------------ #
    # 載入與索引
    # ------------------------------------------------------------------ #
    def maybe_reload(self, force: bool = False) -> None:
        """以 mtime 偵測；變更才重新解析並重建拼音索引（熱重載）。

        任何錯誤都吞掉並沿用上一版成功資料，絕不拋例外。
        """
        try:
            if not self.path.exists():
                return
            mtime = self.path.stat().st_mtime
            if not force and mtime == self._mtime:
                return  # 未變更，不解析

            with open(self.path, encoding="utf-8") as f:
                data = json.load(f)

            self._rebuild(data)
            self._mtime = mtime
        except Exception as e:
            # 解析失敗 → 保留舊資料，僅警告（plan §5 風險表）
            logger.warning("⚠️  user_vocab.json 載入失敗，沿用上一版（%s）", e)

    def _rebuild(self, data: dict) -> None:
        # ── 拼音索引 ──
        pinyin_index: dict[tuple[int, tuple[str, ...]], str] = {}
        lengths: set[int] = set()
        if _PYPINYIN_OK:
            for cat in self._PINYIN_CATEGORIES:
                for term in data.get(cat, []) or []:
                    if not isinstance(term, str):
                        continue
                    term = term.strip()
                    if len(term) < self.min_term_len:
                        continue
                    if not _all_cjk(term):
                        continue  # 非純中文不進拼音引擎
                    key = (len(term), self._pinyin_of(term))
                    # D6：詞彙表已確認無同音同字衝突；若仍重複，先到者優先並警告
                    if key in pinyin_index and pinyin_index[key] != term:
                        logger.warning(
                            "⚠️  詞彙拼音衝突：%r 與 %r 同音同字數，保留前者",
                            pinyin_index[key], term,
                        )
                        continue
                    pinyin_index[key] = term
                    lengths.add(len(term))

        # ── overrides ──
        overrides: dict[str, str] = {}
        raw_ov = data.get("overrides", {}) or {}
        if isinstance(raw_ov, dict):
            for k, v in raw_ov.items():
                if k == "_comment" or not isinstance(v, str):
                    continue
                if k and v:
                    overrides[k] = v

        # ── STT keyterms ──
        keyterms: list[str] = []
        seen: set[str] = set()
        for cat in self._KEYTERM_CATEGORIES:
            for term in data.get(cat, []) or []:
                if isinstance(term, str) and term.strip() and term not in seen:
                    seen.add(term)
                    keyterms.append(term.strip())

        # 一次性換上（避免半套狀態）
        self._pinyin_index = pinyin_index
        self._lengths = sorted(lengths, reverse=True)
        self._overrides = overrides
        self._stt_keyterms = keyterms

    def _pinyin_of(self, s: str) -> tuple[str, ...]:
        return tuple(lazy_pinyin(s, style=self._style))

    # ------------------------------------------------------------------ #
    # 對外介面
    # ------------------------------------------------------------------ #
    @property
    def stt_keyterms(self) -> list[str]:
        """供 STT 使用的詞（people+companies+projects+terms）。"""
        return list(self._stt_keyterms)

    def apply(self, text: str) -> str:
        """第三層主入口：先 overrides 字面替換 → 再拼音 fuzzy 替換。

        任何錯誤都回傳原文，絕不拋例外。
        """
        if not text:
            return text
        try:
            # 1. overrides：字面強制替換（最高優先）
            for wrong, right in self._overrides.items():
                if wrong in text:
                    text = text.replace(wrong, right)

            # 2. 拼音 fuzzy
            if _PYPINYIN_OK and self._pinyin_index:
                text = self._apply_pinyin(text)

            return text
        except Exception as e:
            logger.warning("⚠️  vocab.apply 失敗，回傳原文（%s）", e)
            return text

    def _apply_pinyin(self, text: str) -> str:
        n = len(text)
        claimed = [False] * n  # 已被替換覆蓋的字元位置
        # (start, end, canonical)；由大到小詞長處理，避免子字串先被吃掉
        replacements: list[tuple[int, int, str]] = []

        for L in self._lengths:
            if L > n:
                continue
            for i in range(0, n - L + 1):
                window = text[i:i + L]
                if not _all_cjk(window):
                    continue
                # 已正確就不動
                key = (L, self._pinyin_of(window))
                canonical = self._pinyin_index.get(key)
                if canonical is None or window == canonical:
                    continue
                # require_surname_char_same：需首字相同才替換
                if self.require_surname_char_same and window[0] != canonical[0]:
                    continue
                # 避免與已認領區間重疊
                if any(claimed[j] for j in range(i, i + L)):
                    continue
                for j in range(i, i + L):
                    claimed[j] = True
                replacements.append((i, i + L, canonical))

        if not replacements:
            return text

        # 從後往前替換以保 index 正確
        replacements.sort(key=lambda r: r[0], reverse=True)
        for start, end, canonical in replacements:
            text = text[:start] + canonical + text[end:]
        return text


# ---------------------------------------------------------------------------
# 第一層：Grok STT 關鍵詞
# ---------------------------------------------------------------------------

class Layer1VocabStore:
    """第一層 Grok STT 額外關鍵詞管理（hot-reload via mtime）。"""

    def __init__(self, path: Path):
        self.path = Path(path)
        self._mtime: float | None = None
        self._keyterms: list[str] = []
        self.maybe_reload(force=True)

    def maybe_reload(self, force: bool = False) -> None:
        try:
            if not self.path.exists():
                return
            mtime = self.path.stat().st_mtime
            if not force and mtime == self._mtime:
                return
            with open(self.path, encoding="utf-8") as f:
                data = json.load(f)
            self._keyterms = [
                k.strip() for k in data.get("keyterms", [])
                if isinstance(k, str) and k.strip()
            ]
            self._mtime = mtime
        except Exception as e:
            logger.warning("⚠️  layer1_keyterms.json 載入失敗，沿用上一版（%s）", e)

    @property
    def keyterms(self) -> list[str]:
        return list(self._keyterms)


# ---------------------------------------------------------------------------
# 第二層：Cerebras LLM 修正詞彙
# ---------------------------------------------------------------------------

class Layer2VocabStore:
    """第二層 Cerebras LLM 修正詞彙管理（hot-reload via mtime）。"""

    def __init__(self, path: Path):
        self.path = Path(path)
        self._mtime: float | None = None
        self._names: list[str] = []
        self._corrections: dict[str, str] = {}
        self.maybe_reload(force=True)

    def maybe_reload(self, force: bool = False) -> None:
        try:
            if not self.path.exists():
                return
            mtime = self.path.stat().st_mtime
            if not force and mtime == self._mtime:
                return
            with open(self.path, encoding="utf-8") as f:
                data = json.load(f)
            self._names = [
                n.strip() for n in data.get("names", [])
                if isinstance(n, str) and n.strip()
            ]
            raw_corr = data.get("corrections", {}) or {}
            self._corrections = {
                k: v for k, v in raw_corr.items()
                if k != "_comment" and isinstance(v, str) and k and v
            }
            self._mtime = mtime
        except Exception as e:
            logger.warning("⚠️  layer2_corrections.json 載入失敗，沿用上一版（%s）", e)

    def build_injection(self) -> str:
        """建立動態注入 LLM system prompt 的補充文字。空檔案回傳空字串。"""
        if not self._names and not self._corrections:
            return ""
        parts = []
        if self._names:
            parts.append("以下人名與術語請正確拼寫：" + "、".join(self._names))
        if self._corrections:
            corr_str = "、".join(f"{k}→{v}" for k, v in self._corrections.items())
            parts.append("以下詞語請強制替換：" + corr_str)
        return "\n".join(parts)

    @property
    def names(self) -> list[str]:
        return list(self._names)

    @property
    def corrections(self) -> dict[str, str]:
        return dict(self._corrections)


def load_layer1_vocab(base_dir) -> Layer1VocabStore:
    path = Path(base_dir) / "layer1_keyterms.json"
    store = Layer1VocabStore(path)
    if not path.exists():
        logger.info("ℹ️  layer1_keyterms.json 不存在（建立後存檔即會熱重載）")
    return store


def load_layer2_vocab(base_dir) -> Layer2VocabStore:
    path = Path(base_dir) / "layer2_corrections.json"
    store = Layer2VocabStore(path)
    if not path.exists():
        logger.info("ℹ️  layer2_corrections.json 不存在（建立後存檔即會熱重載）")
    return store


def load_vocab_store(base_dir, config) -> VocabStore | None:
    """依 config 建立 VocabStore；停用或不可用時回傳 None。"""
    vocab_cfg = config.get("vocab", {}) or {}
    if not vocab_cfg.get("enabled", False):
        logger.info("ℹ️  詞彙修正：停用（vocab.enabled=false）")
        return None
    if not _PYPINYIN_OK:
        logger.warning("⚠️  詞彙修正：pypinyin 不可用，僅 overrides 字面替換可運作")
        # 仍建立 store（overrides 與 keyterms 不需 pypinyin）
    try:
        file_name = vocab_cfg.get("file", "user_vocab.json")
        path = Path(base_dir) / file_name
        store = VocabStore(path, vocab_cfg.get("match", {}))
        if not path.exists():
            logger.warning("⚠️  詞彙檔不存在：%s（建立後存檔即會熱重載）", path)
        return store
    except Exception as e:
        logger.warning("⚠️  詞彙修正初始化失敗，整層停用（%s）", e)
        return None
