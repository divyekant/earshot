"""Narrow profile: does a profile of one phrase score free speech lower than a profile of varied speech?
Record: docs/experiments/E6-voice-check.md, section 8.2. Run: uv run python voice_narrow.py.

The owner's profile holds 5 takes of the wake phrase only. Follow-up turns have no phrase. Live test 2026-11-03:
follow-up turns in the owner's voice scored 0.16 to 0.28, wake turns 0.43 to 0.76.

LibriSpeech has no phrase said 5 times. As a stand-in, the narrow profile is 5 takes of the same 0.8 s of one file,
at offsets of 0, 40 and 80 ms each way: the same words, one way of speech. It is a strong case of a narrow profile.
- varied: 5 takes of 0.7 to 1.0 s from 5 files (the E6 bench profile)
- narrow: the stand-in above
- narrow + turns: the narrow takes and 3 passed turns of 2.5 s from other files, all in one mean
Tests: free speech windows of 1.4 s and 2.8 s from other files of the same chapter, and of the other speakers.
"""
import os, sys, numpy as np, soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_bench as vb

LENS = [1.4, 2.8]

def line(seconds):
    return 0.35 + 0.07 * min(1.0, max(0.0, seconds - 1.0))

def unit(v):
    return v / np.linalg.norm(v)

def main():
    sp = vb.load()
    data = {}
    for spk, ch in sp.items():
        files = ch[list(ch)[0]]
        if len(files) < 14: continue
        audio = [sf.read(f, dtype="float32")[0] for f in files]
        # narrow: one 0.8 s window of the first file that has one, at 5 offsets
        narrow = None
        for x in audio[:3]:
            w = vb.speech_window(x, 0.96)
            if w is None: continue
            n = int(0.8 * vb.RATE)
            narrow = [vb.trim(w[o:o + n]) for o in (0, 640, 1280)] + [vb.trim(w[640:640 + n]), vb.trim(w[960:960 + n])]
            break
        if narrow is None: continue
        varied = [vb.trim(w) for w in (vb.speech_window(x, vb.RNG.uniform(0.7, 1.0)) for x in audio[3:9]) if w is not None][:5]
        turns = [vb.trim(w) for w in (vb.speech_window(x, 2.5) for x in audio[9:13]) if w is not None][:3]
        tests = [w for w in (vb.speech_window(x, max(LENS)) for x in audio[13:33]) if w is not None]
        if len(varied) < 5 or len(turns) < 3 or len(tests) < 5: continue
        en = np.array([vb.embed(a, "zero") for a in narrow])
        ev = np.array([vb.embed(a, "zero") for a in varied])
        et = np.array([vb.embed(a, "zero") for a in turns])
        prof = {"varied": unit(ev.mean(0)), "narrow": unit(en.mean(0)),
                "narrow + turns": unit(np.vstack([en, et]).mean(0))}
        t = {}
        for L in LENS:
            clips = [vb.trim(a[:int(L * vb.RATE)]) for a in tests]
            t[L] = (np.array([vb.embed(c, "zero") for c in clips]), np.array([len(c) / vb.RATE for c in clips]))
        data[spk] = (prof, t)
        print(spk, len(tests), file=sys.stderr, flush=True)

    print(f"speakers {len(data)}")
    for L in LENS:
        for name in ("varied", "narrow", "narrow + turns"):
            own, own_lim, imp, imp_lim = [], [], [], []
            for s, (prof, t) in data.items():
                E, sec = t[L]
                own += list(E @ prof[name]); own_lim += [line(x) for x in sec]
                for o, (_, to) in data.items():
                    if o == s: continue
                    Eo, seco = to[L]
                    imp += list(Eo @ prof[name]); imp_lim += [line(x) for x in seco]
            own, own_lim, imp, imp_lim = map(np.array, (own, own_lim, imp, imp_lim))
            print(f"{L:.1f} s {name:15s}: owner median {np.median(own):.2f}, p10 {np.quantile(own, 0.1):.2f}, "
                  f"pass {np.mean(own >= own_lim)*100:5.1f}% | other median {np.median(imp):.2f}, "
                  f"pass {np.mean(imp >= imp_lim)*100:5.2f}% ({len(own)} owner, {len(imp)} other)")

main()
