"""Far-field test commands: the owner taught earshot at the desk, then speaks across the room.
Each command gets a synthetic room echo (RT60 0.3 to 0.7 s, direct-to-echo ratio -3 to +3 dB) and pink
noise at 20 dB SNR. 6 commands per voice and phrase. Usage: gen_far.py <voice index>"""
import os
import sys

import numpy as np
from scipy.signal import fftconvolve

import tts
from gen import COMMANDS, OUT, PHRASES, VOICES, mix, pink
from kws import Kws


def room(rng, rate=16000):
    rt60 = rng.uniform(0.3, 0.7)
    n = int(rt60 * rate)
    t = np.arange(n) / rate
    tail = rng.standard_normal(n) * np.exp(-6.9 * t / rt60)
    tail[: int(0.003 * rate)] = 0  # first reflections come after the direct sound
    drr_db = rng.uniform(-3, 3)
    tail *= 1.0 / (np.sqrt((tail ** 2).sum()) * 10 ** (drr_db / 20))
    h = tail
    h[0] = 1.0
    return h.astype(np.float32)


def main():
    vi = int(sys.argv[1])
    model, spk = VOICES[vi]
    vname = f"{model}{spk}"
    rng = np.random.default_rng(500 + vi)
    k = Kws()
    sil = lambda s: np.zeros(int(s * 16000), np.float32)
    for phrase in PHRASES:
        dest = f"{OUT}/{vname}/{phrase.replace(' ', '_')}_far.npz"
        if os.path.exists(dest):
            continue
        cap = phrase[0].upper() + phrase[1:]
        frames, spans = [], []
        for j in range(6):
            p = tts.say(model, spk, rng.choice([phrase, cap + ",", cap]), rng)
            c = tts.say(model, spk, COMMANDS[(j + 6) % len(COMMANDS)], rng)
            pre = np.concatenate([sil(1.0), sil(rng.uniform(0.3, 0.9))])
            clip = np.concatenate([pre, p, sil(rng.uniform(0.0, 0.2)), c, sil(1.0)])
            wet = fftconvolve(clip, room(rng))[: len(clip)].astype(np.float32)
            wet *= np.max(np.abs(clip)) / (np.max(np.abs(wet)) + 1e-9) * 0.5  # farther = quieter
            wet = mix(wet, pink(len(wet), rng), 20)
            frames.append(k.encode(wet).astype(np.float16))
            spans.append([len(pre) / 16000, (len(pre) + len(p)) / 16000])
        np.savez_compressed(dest + ".tmp.npz", test=np.array(frames, dtype=object), test_span=np.array(spans))
        os.replace(dest + ".tmp.npz", dest)
        print(vname, phrase, "far done", flush=True)


if __name__ == "__main__":
    main()
