"""Makes the synthetic bench data for one voice: enrolment takes, test commands, own talk, sound-alikes.

Each voice says each phrase 10 times alone (enrolment), and 12 times before a command (test).
The test clips start with silence or with a sentence of the voice's own talk, and a third get
pink noise (15 dB SNR) and a third get babble from LibriSpeech (10 dB SNR).
The voice also reads about 6 minutes of LibriSpeech text (own talk, no phrase).
Usage: gen.py <voice index>"""
import glob
import json
import os
import sys

import numpy as np
import soundfile as sf

import tts
from kws import Kws
from paths import DATA

OUT = os.path.join(DATA, "gen")
LIBRI = os.path.join(DATA, "libri", "LibriSpeech")

PHRASES = {
    "hey jarvis": ["hey, Travis", "hey, service", "Jarvis is a common name", "hey, Charles"],
    "hey atlas": ["here at least", "hey, at last", "the atlas is on the shelf", "hey, Alice", "at least we tried"],
    "hey earshot": ["hey, your shot", "keep it out of earshot", "hey, here's what", "hey, nice shot"],
    "okay nova": ["okay, no man", "okay, nobody", "I like bossa nova", "okay, now go"],
    "hey kairo": ["hey, Cairo", "hey, Kyle", "hey, Carol", "a hero"],
    "hey zorbix": ["hey, zebras", "the Sorbonne", "hey, sir Rick", "hey, Sorbets"],
    "hey computer": ["hey, come here", "my computer is slow", "hey, compute it", "the computer is on"],
    "arre suno": ["are you sure", "hurry soon", "are you new", "a reason"],
}
ENROL_FORMS = ["{p}", "{P}.", "{P}!", "{p}", "{P}?"]
COMMANDS = ["open Slack", "type hello there", "scroll down", "what time is it", "go to the Claude window",
            "click on refresh", "open Notes", "play the next song", "search for flights", "close this tab",
            "open Calendar", "read the last message"]
# 10 voices from 3 Piper models: (model, speaker id)
VOICES = [("libritts", 12), ("libritts", 140), ("libritts", 377), ("libritts", 590),
          ("vctk", 2), ("vctk", 40), ("vctk", 77), ("arctic", 0), ("arctic", 5), ("arctic", 11)]


def libri_texts(n, rng):
    texts = []
    for f in sorted(glob.glob(f"{LIBRI}/test-other/*/*/*.trans.txt")):
        for line in open(f):
            texts.append(line.split(" ", 1)[1].strip().lower())
    rng.shuffle(texts)
    return texts[:n]


def pink(n, rng):
    x = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(len(x)); f[0] = 1
    y = np.fft.irfft(x / np.sqrt(f), n)
    return (y / (np.std(y) + 1e-9)).astype(np.float32)


def babble(n, rng, files):
    out = np.zeros(n, np.float32)
    for f in rng.choice(files, 4, replace=False):
        a, _ = sf.read(f, dtype="float32")
        a = np.resize(a, n)
        out += a / (np.std(a) + 1e-9)
    return out / (np.std(out) + 1e-9)


def mix(clean, noise, snr_db):
    p = np.std(clean[np.abs(clean) > 0.01]) if np.any(np.abs(clean) > 0.01) else np.std(clean)
    return (clean + noise * p / (10 ** (snr_db / 20))).astype(np.float32)


def main():
    vi = int(sys.argv[1])
    model, spk = VOICES[vi]
    vname = f"{model}{spk}"
    rng = np.random.default_rng(100 + vi)
    k = Kws()
    os.makedirs(f"{OUT}/{vname}", exist_ok=True)
    babble_files = sorted(glob.glob(f"{LIBRI}/test-clean/*/*/*.flac"))
    own = libri_texts(400, rng)
    sil = lambda s: np.zeros(int(s * 16000), np.float32)

    # Own talk: about 6 minutes, one stream with short pauses.
    dest = f"{OUT}/{vname}/own.npz"
    if not os.path.exists(dest):
        parts, total = [], 0.0
        for t in own[40:]:
            a = tts.say(model, spk, t, rng)
            parts += [a, sil(rng.uniform(0.2, 0.7))]
            total += len(a) / 16000
            if total > 360:
                break
        audio = np.concatenate(parts)
        np.savez_compressed(dest + ".tmp.npz", frames=k.encode(audio).astype(np.float16), seconds=len(audio) / 16000)
        os.replace(dest + ".tmp.npz", dest)

    meta = {}
    for pi, (phrase, alikes) in enumerate(PHRASES.items()):
        key = phrase.replace(" ", "_")
        dest = f"{OUT}/{vname}/{key}.npz"
        if os.path.exists(dest):
            continue
        cap = phrase[0].upper() + phrase[1:]
        enrol_audio, enrol_frames = [], []
        for j in range(10):
            text = ENROL_FORMS[j % len(ENROL_FORMS)].format(p=phrase, P=cap)
            a = tts.say(model, spk, text, rng)
            enrol_audio.append(a)
            enrol_frames.append(k.encode(np.concatenate([sil(0.3), a, sil(0.3)])).astype(np.float16))
        tests = []
        for j in range(12):
            p = tts.say(model, spk, rng.choice([phrase, cap + ",", cap]), rng)
            c = tts.say(model, spk, COMMANDS[j], rng)
            lead = tts.say(model, spk, own[j], rng) if j % 2 else sil(0)
            pre = np.concatenate([sil(1.0), lead, sil(rng.uniform(0.1, 0.4) if j % 2 else rng.uniform(0.3, 0.9))])
            clip = np.concatenate([pre, p, sil(rng.uniform(0.0, 0.2)), c, sil(1.0)])
            start, end = len(pre) / 16000, (len(pre) + len(p)) / 16000
            cond = ["clean", "pink15", "babble10"][j % 3]
            if cond == "pink15":
                clip = mix(clip, pink(len(clip), rng), 15)
            elif cond == "babble10":
                clip = mix(clip, babble(len(clip), rng, babble_files), 10)
            tests.append((k.encode(clip).astype(np.float16), start, end, cond, j % 2 == 1))
        alike_frames = []
        for t in alikes:
            for _ in range(3):
                a = tts.say(model, spk, t, rng)
                alike_frames.append(k.encode(np.concatenate([sil(0.5), a, sil(0.5)])).astype(np.float16))
        np.savez_compressed(
            dest + ".tmp.npz",
            enrol=np.array(enrol_frames, dtype=object),
            enrol_audio=np.array(enrol_audio, dtype=object),
            test=np.array([t[0] for t in tests], dtype=object),
            test_span=np.array([[t[1], t[2]] for t in tests]),
            test_cond=np.array([t[3] for t in tests]),
            test_lead=np.array([t[4] for t in tests]),
            alike=np.array(alike_frames, dtype=object),
        )
        os.replace(dest + ".tmp.npz", dest)
        meta[phrase] = len(tests)
        print(vname, phrase, "done", flush=True)


if __name__ == "__main__":
    main()
