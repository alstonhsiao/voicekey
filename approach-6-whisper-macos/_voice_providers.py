"""STT + LLM provider 抽象與實作"""
from __future__ import annotations

import logging
import os

import requests

from _voice_config import Mode

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# STT providers
# ---------------------------------------------------------------------------

class TranscribeProvider:
    """Provider 介面。子類實作 transcribe(wav_path, mode) -> str"""
    name = "base"

    def __init__(self, cfg: dict):
        self.cfg = cfg

    def transcribe(self, wav_path: str, mode: Mode) -> str:
        raise NotImplementedError


class OpenAIProvider(TranscribeProvider):
    name = "openai"

    def transcribe(self, wav_path, mode):
        url = self.cfg["endpoint"]
        headers = {"Authorization": f"Bearer {self.cfg['api_key']}"}
        with open(wav_path, "rb") as f:
            files = {"file": ("voice.wav", f, "audio/wav")}
            data = {
                "model": self.cfg["model"],
                "language": mode.language,
                "temperature": str(self.cfg.get("temperature", 0.0)),
                "response_format": "text",
                "prompt": mode.prompt,
            }
            if mode.translate_to_english:
                url = url.replace("/transcriptions", "/translations")
                data.pop("language", None)
            r = requests.post(url, headers=headers, files=files, data=data, timeout=30)
        r.raise_for_status()
        return r.text.strip()


class GroqProvider(TranscribeProvider):
    """Groq API 與 OpenAI 格式相容"""
    name = "groq"

    def transcribe(self, wav_path, mode):
        return OpenAIProvider.transcribe(self, wav_path, mode)


class GrokProvider(TranscribeProvider):
    """xAI Grok STT — https://api.x.ai/v1/stt
    欄位：file（最後）、language、keyterm（可重複，對應 prompt 關鍵詞）
    無 model 欄位；回應：JSON {"text":"...", "language":"...", "duration":N}
    """
    name = "grok"

    def transcribe(self, wav_path, mode):
        url = self.cfg["endpoint"]
        headers = {"Authorization": f"Bearer {self.cfg['api_key']}"}
        lang = "en" if mode.translate_to_english else mode.language
        keyterms = mode.grok_keyterms[:10]
        fields = [("language", lang)]
        for kt in keyterms:
            if len(kt) <= 50:
                fields.append(("keyterm", kt))
        with open(wav_path, "rb") as f:
            files = {"file": ("voice.wav", f, "audio/wav")}
            r = requests.post(
                url, headers=headers,
                data=fields,
                files=files,
                timeout=30,
            )
        r.raise_for_status()
        try:
            return r.json().get("text", "").strip()
        except ValueError:
            return r.text.strip()


def build_provider(api_cfg: dict) -> TranscribeProvider:
    name = api_cfg.get("provider", "grok").lower()
    sub = dict(api_cfg.get(name, {}))
    sub["temperature"] = api_cfg.get("temperature", 0.0)
    if not sub.get("api_key"):
        raise RuntimeError(f"❌ {name} provider 缺少 api_key（請設定對應環境變數）")
    providers = {
        "openai": OpenAIProvider,
        "grok": GrokProvider,
        "groq": GroqProvider,
    }
    if name not in providers:
        raise RuntimeError(f"❌ 未知的 provider：{name}")
    return providers[name](sub)


# ---------------------------------------------------------------------------
# LLM 修正 providers
# ---------------------------------------------------------------------------

class LLMCorrectionProvider:
    """LLM 後處理介面。子類實作 correct(text, mode) -> str"""
    name = "base_llm"

    def correct(self, text: str, mode: Mode) -> str:
        raise NotImplementedError


class CerebrasProvider(LLMCorrectionProvider):
    """Cerebras 快速 LLM 修正（Llama / Qwen）"""
    name = "cerebras"

    def __init__(self, cfg: dict):
        self.cfg = cfg

    def correct(self, text: str, mode: Mode, extra_system_prompt: str = "") -> str:
        self.last_finish_reason: str | None = None
        if not mode.llm_prompt or not text:
            return text
        try:
            url = self.cfg.get("endpoint", "https://api.cerebras.ai/v1/chat/completions")
            headers = {
                "Authorization": f"Bearer {self.cfg['api_key']}",
                "Content-Type": "application/json",
            }
            system_prompt = mode.llm_prompt
            if extra_system_prompt:
                system_prompt = system_prompt + "\n\n" + extra_system_prompt
            data = {
                "model": self.cfg.get("model", "llama3.3-70b"),
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user",   "content": text},
                ],
                "max_tokens": self.cfg.get("max_tokens", 512),
                "temperature": 0.0,
            }
            r = requests.post(url, headers=headers, json=data, timeout=15)
            r.raise_for_status()
            res = r.json()
            choice = res["choices"][0]
            self.last_finish_reason = choice.get("finish_reason")
            if self.last_finish_reason == "length":
                logger.warning(
                    "⚠️  Cerebras 輸出被截斷（finish_reason=length，max_tokens=%s）",
                    self.cfg.get("max_tokens", 512),
                )
            return choice["message"]["content"].strip()
        except Exception as e:
            logger.warning("⚠️  Cerebras 修正失敗（%s），使用原始文字", e)
            return text


def build_llm_correction_provider(api_cfg: dict) -> LLMCorrectionProvider | None:
    llm_cfg = api_cfg.get("llm_correction", {})
    provider_name = llm_cfg.get("provider", "none").lower()
    if provider_name == "none" or not llm_cfg:
        return None
    sub = dict(llm_cfg.get(provider_name, {}))

    env_key = os.environ.get("CEREBRAS_API_KEY")
    if env_key:
        sub["api_key"] = env_key

    if not sub.get("api_key"):
        raise RuntimeError(f"❌ llm_correction.{provider_name} 缺少 api_key")

    providers = {"cerebras": CerebrasProvider}
    if provider_name not in providers:
        logger.warning("⚠️ 找不到 llm_correction provider: %s，已停用修正。", provider_name)
        return None

    return providers[provider_name](sub)
