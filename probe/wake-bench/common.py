"""Shared helpers for the bench: data loading, template trimming, peak picking."""
from __future__ import annotations

import glob
import os

import numpy as np
from paths import DATA

GEN = os.path.join(DATA, "gen")
LIBRI_FRAMES = os.path.join(DATA, "libri_frames")
FRAME_S = 0.04


def speech_span(audio: np.ndarray, rate: int = 16000) -> tuple[float, float]:
    """The same rule as SpeechTrim in Swift, without the 150 ms pad: first and last loud 20 ms frame."""
    frame = rate // 50
    n = len(audio) // frame
    if n == 0:
        return 0.0, 0.0
    x = audio[: n * frame].reshape(n, frame).astype(np.float64)
    rms = np.sqrt((x ** 2).mean(axis=1))
    lv = np.where(rms > 0, 20 * np.log10(np.maximum(rms, 1e-12)), -120)
    floor = np.sort(lv)[n // 10]
    thr = max(floor + 12, -50)
    loud = np.nonzero(lv >= thr)[0]
    if len(loud) == 0:
        return 0.0, len(audio) / rate
    return loud[0] * frame / rate, (loud[-1] + 1) * frame / rate


def template(frames: np.ndarray, audio: np.ndarray, lead_s: float = 0.3, delay: int = 1,
             pad: int = 1) -> np.ndarray:
    """The frames of the spoken part of one enrolment take."""
    s, e = speech_span(audio)
    f0 = max(0, int(round((lead_s + s) / FRAME_S)) + delay - pad)
    f1 = min(len(frames), int(round((lead_s + e) / FRAME_S)) + delay + pad)
    return frames[f0:f1]


def voices() -> list[str]:
    return sorted(os.path.basename(p) for p in glob.glob(f"{GEN}/*") if os.path.isdir(p))


def load(voice: str, phrase: str):
    return np.load(f"{GEN}/{voice}/{phrase.replace(' ', '_')}.npz", allow_pickle=True)


def own(voice: str):
    d = np.load(f"{GEN}/{voice}/own.npz", allow_pickle=True)
    return d["frames"].astype(np.float32), float(d["seconds"])


def libri(names: list[str] | None = None):
    """(name, frames) for each chapter stream. The first 12 chapters of test-other are the
    calibration bank (B); the others are the test set."""
    files = sorted(glob.glob(f"{LIBRI_FRAMES}/*.npy"))
    for f in files:
        n = os.path.basename(f)[:-4]
        if names is None or n in names:
            yield n, np.load(f).astype(np.float32)


def nms_minima(s: np.ndarray, radius: int = 38) -> np.ndarray:
    """Values of the local minima of s, at least `radius` frames apart (best first).
    The count of values below a threshold is the count of wakes at that threshold."""
    if len(s) == 0:
        return np.zeros(0, np.float32)
    finite = np.isfinite(s)
    s2 = np.where(finite, s, np.inf)
    # candidates: local minima
    left = np.concatenate([[np.inf], s2[:-1]])
    right = np.concatenate([s2[1:], [np.inf]])
    cand = np.nonzero((s2 <= left) & (s2 < right) & finite)[0]
    if len(cand) == 0:
        return np.zeros(0, np.float32)
    order = cand[np.argsort(s2[cand])]
    taken = np.zeros(len(s2), bool)
    out = []
    for i in order:
        if taken[i]:
            continue
        out.append(s2[i])
        taken[max(0, i - radius): i + radius + 1] = True
    return np.array(out, np.float32)


def nms_idx(s: np.ndarray, radius: int = 38, cap: float = 0.6) -> np.ndarray:
    """Frame indexes of the local minima of s below cap, at least `radius` frames apart."""
    if len(s) == 0:
        return np.zeros(0, np.int64)
    s2 = np.where(np.isfinite(s), s, np.inf)
    left = np.concatenate([[np.inf], s2[:-1]])
    right = np.concatenate([s2[1:], [np.inf]])
    cand = np.nonzero((s2 <= left) & (s2 < right) & (s2 < cap))[0]
    order = cand[np.argsort(s2[cand])]
    taken = np.zeros(len(s2), bool)
    out = []
    for i in order:
        if taken[i]:
            continue
        out.append(i)
        taken[max(0, i - radius): i + radius + 1] = True
    return np.array(out, np.int64)
