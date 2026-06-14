"""音訊錄音模組"""
from __future__ import annotations

import logging
import os
import tempfile

import numpy as np
import sounddevice as sd
import soundfile as sf

logger = logging.getLogger(__name__)


class AudioRecorder:
    """使用 sounddevice 在記憶體中錄音，stop() 回傳隨機 NamedTemp WAV 路徑。"""

    def __init__(
        self,
        sample_rate: int = 16000,
        channels: int = 1,
        input_device: int | str | None = None,
    ):
        self.sample_rate = sample_rate
        self.channels = channels
        self.input_device = input_device
        self.input_device_id = self._resolve_input_device(input_device)
        self.is_recording = False
        self._frames: list[np.ndarray] = []
        self._stream: sd.InputStream | None = None
        self.last_stats: dict[str, float | str | int | None] = {}

    @staticmethod
    def _find_device_by_name(name: str) -> int | None:
        """依名稱（完整或部分）找 input device id，找不到回傳 None。"""
        needle = name.strip().lower()
        devices = sd.query_devices()
        input_devices = [(i, d) for i, d in enumerate(devices) if d["max_input_channels"] > 0]
        exact = [i for i, d in input_devices if str(d["name"]).strip().lower() == needle]
        if exact:
            return exact[0]
        partial = [i for i, d in input_devices if needle in str(d["name"]).strip().lower()]
        return partial[0] if partial else None

    @staticmethod
    def _resolve_input_device(input_device: int | str | list | None) -> int | None:
        if input_device in (None, ""):
            return None
        if isinstance(input_device, int):
            info = sd.query_devices(input_device)
            if info["max_input_channels"] <= 0:
                raise ValueError(f"錄音裝置 {input_device} 不是 input device")
            return input_device

        # 支援 list：依序嘗試，返回第一個在此機器上存在的裝置
        if isinstance(input_device, list):
            candidates = [c for c in input_device if c not in (None, "")]
            for candidate in candidates:
                device_id = AudioRecorder._find_device_by_name(str(candidate))
                if device_id is not None:
                    logger.info("🎙️  自動選擇裝置：%r（候選清單：%s）", candidate, candidates)
                    return device_id
            logger.warning("⚠️  候選裝置均不可用：%s；改用系統預設輸入", candidates)
            return None

        device_id = AudioRecorder._find_device_by_name(str(input_device))
        if device_id is not None:
            return device_id
        devices = sd.query_devices()
        available = ", ".join(
            f"{i}:{d['name']}" for i, d in enumerate(devices) if d["max_input_channels"] > 0
        )
        raise ValueError(f"找不到 input device {input_device!r}；可用裝置：{available}")

    def input_device_label(self) -> str:
        device_id = self.input_device_id
        if device_id is None:
            default_id = sd.default.device[0]
            if default_id is None or default_id < 0:
                return "system default input"
            device_id = default_id
        info = sd.query_devices(device_id)
        return f"{device_id}:{info['name']}"

    def start(self):
        self._frames = []
        self.last_stats = {}
        self.is_recording = True
        logger.info("🎙️  錄音裝置：%s", self.input_device_label())
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype="int16",
            device=self.input_device_id,
            callback=self._callback,
        )
        self._stream.start()

    def _callback(self, indata, frames, time_info, status):
        if status:
            logger.warning("⚠️  音訊輸入狀態：%s", status)
        if self.is_recording:
            self._frames.append(indata.copy())

    def stop(self) -> tuple[str | None, float]:
        """停止錄音並寫入 NamedTemporaryFile WAV，回傳 (路徑, 秒數)。
        呼叫者負責用後 os.unlink(path) 刪除暫存檔。"""
        self.is_recording = False
        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None

        if not self._frames:
            return None, 0.0

        audio_data = np.concatenate(self._frames, axis=0)
        duration = len(audio_data) / self.sample_rate
        x = audio_data.astype(np.float32).reshape(-1) / 32768.0
        rms = float(np.sqrt(np.mean(x * x))) if len(x) else 0.0
        peak = float(np.max(np.abs(x))) if len(x) else 0.0
        self.last_stats = {
            "device": self.input_device_label(),
            "rms": rms,
            "peak": peak,
            "rms_dbfs": 20 * np.log10(rms) if rms > 0 else None,
            "peak_dbfs": 20 * np.log10(peak) if peak > 0 else None,
        }
        logger.info(
            "🎚️  錄音音量：RMS %.1f dBFS / Peak %.1f dBFS",
            self.last_stats["rms_dbfs"] if self.last_stats["rms_dbfs"] is not None else -120.0,
            self.last_stats["peak_dbfs"] if self.last_stats["peak_dbfs"] is not None else -120.0,
        )
        if duration < 0.5:
            return None, duration

        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        tmp.close()
        sf.write(tmp.name, audio_data, self.sample_rate, subtype="PCM_16")
        return tmp.name, duration

    @property
    def buffer_samples(self) -> int:
        return sum(len(f) for f in self._frames)
