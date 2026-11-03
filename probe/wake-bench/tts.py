"""Synthetic voices for the bench: Piper multi-speaker models, resampled to 16 kHz mono."""
from __future__ import annotations

import os
import numpy as np
from scipy.signal import resample_poly
from piper import PiperVoice
from piper.config import SynthesisConfig
from paths import DATA

PIPER_DIR = os.path.join(DATA, "piper")
MODELS = {
    "libritts": "en_US-libritts_r-medium.onnx",
    "vctk": "en_GB-vctk-medium.onnx",
    "arctic": "en_US-arctic-medium.onnx",
}
_voices: dict[str, PiperVoice] = {}


def voice(model: str) -> PiperVoice:
    if model not in _voices:
        _voices[model] = PiperVoice.load(os.path.join(PIPER_DIR, MODELS[model]))
    return _voices[model]


def say(model: str, speaker: int, text: str, rng: np.random.Generator, vary: bool = True) -> np.ndarray:
    """One rendering at 16 kHz. With vary, the speed and the prosody noise change at random,
    so that two renderings of one text by one voice differ (as two takes by one person do)."""
    v = voice(model)
    if vary:
        cfg = SynthesisConfig(speaker_id=speaker, length_scale=float(rng.uniform(0.8, 1.25)),
                              noise_scale=float(rng.uniform(0.5, 0.9)), noise_w_scale=float(rng.uniform(0.6, 1.0)))
    else:
        cfg = SynthesisConfig(speaker_id=speaker)
    chunks = [c.audio_float_array for c in v.synthesize(text, syn_config=cfg)]
    audio = np.concatenate(chunks).astype(np.float32) if chunks else np.zeros(0, np.float32)
    rate = v.config.sample_rate
    if rate != 16000:
        g = np.gcd(rate, 16000)
        audio = resample_poly(audio, 16000 // g, rate // g).astype(np.float32)
    return audio
