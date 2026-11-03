"""Encoder frames of LibriSpeech test-clean and test-other, one stream for each chapter.
The utterances of a chapter are joined with 0.3 to 0.8 s of silence, as in one long talk.
Usage: libri_frames.py <part index> <part count>"""
import glob
import os
import sys

import numpy as np
import soundfile as sf

from kws import Kws
from paths import DATA

ROOT = os.path.join(DATA, "libri", "LibriSpeech")
OUT = os.path.join(DATA, "libri_frames")


def main():
    part, parts = int(sys.argv[1]), int(sys.argv[2])
    os.makedirs(OUT, exist_ok=True)
    chapters = sorted(glob.glob(f"{ROOT}/test-*/*/*"))
    k = Kws()
    rng = np.random.default_rng(7)
    for i, ch in enumerate(chapters):
        if i % parts != part:
            continue
        name = ch.split("LibriSpeech/")[1].replace("/", "_")
        dest = f"{OUT}/{name}.npy"
        if os.path.exists(dest):
            continue
        pieces = []
        for f in sorted(glob.glob(f"{ch}/*.flac")):
            a, _ = sf.read(f, dtype="float32")
            pieces.append(a)
            pieces.append(np.zeros(int(rng.uniform(0.3, 0.8) * 16000), np.float32))
        audio = np.concatenate(pieces)
        frames = k.encode(audio)
        np.save(dest, frames.astype(np.float16))
        print(name, len(audio) / 16000, frames.shape, flush=True)


if __name__ == "__main__":
    main()
