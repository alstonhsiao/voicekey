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

    def __init__(self, sample_rate: int = 16000, channels: int = 1):
        self.sample_rate = sample_rate
        self.channels = channels
        self.is_recording = False
        self._frames: list[np.ndarray] = []
        self._stream: sd.InputStream | None = None

    def start(self):
        self._frames = []
        self.is_recording = True
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype="int16",
            callback=self._callback,
        )
        self._stream.start()

    def _callback(self, indata, frames, time_info, status):
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
        if duration < 0.5:
            return None, duration

        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        tmp.close()
        sf.write(tmp.name, audio_data, self.sample_rate, subtype="PCM_16")
        return tmp.name, duration

    @property
    def buffer_samples(self) -> int:
        return sum(len(f) for f in self._frames)
