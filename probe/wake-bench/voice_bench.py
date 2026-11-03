"""E6 voice check bench: the WeSpeaker ResNet34-LM ONNX twin of the app's Core ML model, on Mini LibriSpeech.
Record: docs/experiments/E6-voice-check.md. Run: uv run python voice_bench.py (padding and score rules).

Questions:
1. Does the zero padding to the Core ML enumerated lengths change the scores?
2. How much does a longer clip (phrase + command) help?
3. Mean embedding against max / top-2 of the teach takes.
4. The same in a far condition (room echo, lower level, noise).
"""
import glob, os, sys, json
import numpy as np
import soundfile as sf
import onnxruntime as ort

from paths import DATA as ROOT

DATA = os.path.join(ROOT, "voice")   # wespeaker.onnx and LibriSpeech/dev-clean-2
RNG = np.random.default_rng(7)
LENGTHS = [20, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000]
RATE = 16000

# ---------- features: the app's MelFeatureExtractor ----------
def _filterbank():
    n_fft, n_mels = 512, 80
    def hz2mel(h): return 2595 * np.log10(1 + h / 700)
    def mel2hz(m): return 700 * (10 ** (m / 2595) - 1)
    bins = n_fft // 2 + 1
    freqs = np.arange(bins) * RATE / n_fft
    mels = np.linspace(hz2mel(20.0), hz2mel(RATE / 2), n_mels + 2)
    f = mel2hz(mels)
    diff = np.diff(f)
    fb = np.zeros((bins, n_mels))
    for m in range(n_mels):
        down = (freqs - f[m]) / diff[m]
        up = (f[m + 2] - freqs) / diff[m + 1]
        fb[:, m] = np.maximum(0, np.minimum(down, up)) * (2.0 / (f[m + 2] - f[m]))
    return fb

FB = _filterbank()
WIN = 0.54 - 0.46 * np.cos(2 * np.pi * np.arange(400) / 399)

def mel(audio):
    x = np.asarray(audio, dtype=np.float64)
    e = np.empty_like(x); e[0] = x[0]; e[1:] = x[1:] - 0.97 * x[:-1]
    p = np.pad(e, 200, mode="reflect")
    n = (len(p) - 400) // 160 + 1
    idx = np.arange(400)[None, :] + 160 * np.arange(n)[:, None]
    frames = p[idx] * WIN
    spec = np.abs(np.fft.rfft(frames, n=512)) ** 2
    m = np.log(np.maximum(spec @ FB, 1e-10))
    return (m - m.mean(axis=0)).astype(np.float32)

SESSION = ort.InferenceSession(os.path.join(DATA, "wespeaker.onnx"), providers=["CPUExecutionProvider"])

def embed(audio, pad):
    f = mel(audio)
    t = len(f)
    if pad != "exact":
        length = next((l for l in LENGTHS if l >= t), LENGTHS[-1])
        if pad == "zero":
            g = np.zeros((length, 80), np.float32); g[:min(t, length)] = f[:length]
        elif pad == "repeat":
            reps = int(np.ceil(length / t))
            g = np.tile(f, (reps, 1))[:length]
        f = g
    e = SESSION.run(None, {"feats": f[None]})[0][0]
    return e / np.linalg.norm(e)

# ---------- speech trim: the app's SpeechTrim ----------
def loud_frames(x):
    fr = RATE // 50
    n = len(x) // fr
    if n == 0: return np.zeros(0, bool)
    rms = np.sqrt((x[:n * fr].reshape(n, fr).astype(np.float64) ** 2).mean(1))
    db = np.where(rms > 0, 20 * np.log10(np.maximum(rms, 1e-12)), -120)
    floor = np.sort(db)[n // 10]
    return db >= max(floor + 12, -50)

def trim(x):
    loud = loud_frames(x)
    if not loud.any(): return x
    fr = RATE // 50; pad = RATE * 15 // 100
    i = np.argmax(loud); j = len(loud) - 1 - np.argmax(loud[::-1])
    return x[max(0, i * fr - pad):min(len(x), (j + 1) * fr + pad)]

# ---------- clips ----------
def speech_window(x, seconds):
    """A window of the audio that starts at a loud frame and is mostly speech."""
    n = int(seconds * RATE)
    loud = loud_frames(x)
    fr = RATE // 50
    for _ in range(50):
        if len(x) <= n + RATE // 5: return None
        s = RNG.integers(0, len(x) - n)
        a, b = s // fr, (s + n) // fr
        if loud[a] and loud[a:b].mean() > 0.65:
            return x[s:s + n]
    return None

def far(x):
    """Room echo (RT60 about 0.5 s), half the level, pink noise at 20 dB SNR."""
    t = np.arange(int(0.5 * RATE)) / RATE
    rir = RNG.standard_normal(len(t)) * np.exp(-6.9 * t / 0.5)
    rir[0] = 1.0
    rir /= np.sqrt((rir ** 2).sum())
    y = np.convolve(x, rir)[:len(x)] * 0.5
    white = RNG.standard_normal(len(y))
    f = np.fft.rfft(white); f /= np.sqrt(np.arange(1, len(f) + 1)); pink = np.fft.irfft(f, n=len(y))
    p_sig = (y ** 2).mean(); p_n = (pink ** 2).mean()
    return (y + pink * np.sqrt(p_sig / (p_n * 10 ** 2))).astype(np.float32)

def load():
    root = os.path.join(DATA, "LibriSpeech", "dev-clean-2")
    speakers = {}
    for spk in sorted(os.listdir(root)):
        chapters = sorted(os.listdir(os.path.join(root, spk)))
        files = {c: sorted(glob.glob(os.path.join(root, spk, c, "*.flac"))) for c in chapters}
        speakers[spk] = files
    return speakers

PHRASE = [0.6, 0.8, 1.0]   # the trimmed phrase clip: about 0.3 to 0.7 s of speech plus 2 x 150 ms
TURN = 2.5                  # the phrase and a short command

def main():
    speakers = load()
    clips = {}   # spk -> {"teach": [..], "test": {(kind, seconds): [..]}}
    for spk, chapters in speakers.items():
        names = list(chapters)
        teach_files = chapters[names[0]][:8]
        other = [f for c in names[1:] for f in chapters[c]] or chapters[names[0]][8:]
        if len(other) < 10: other = chapters[names[0]][8:]
        teach = []
        for f in teach_files:
            x, _ = sf.read(f, dtype="float32")
            w = speech_window(x, RNG.uniform(0.7, 1.0))
            if w is not None: teach.append(trim(w))
            if len(teach) == 5: break
        test = {}
        for f in other[:24]:
            x, _ = sf.read(f, dtype="float32")
            for sec in PHRASE + [TURN]:
                w = speech_window(x, sec)
                if w is None: continue
                test.setdefault(("near", sec), []).append(trim(w))
                test.setdefault(("far", sec), []).append(trim(far(w)))
        clips[spk] = {"teach": teach, "test": test, "cross": len(names) > 1}
        print(spk, len(teach), {k: len(v) for k, v in test.items() if k[0] == "near"}, file=sys.stderr)

    results = {}
    for pad in ["zero", "exact", "repeat"]:
        emb = {}
        for spk, c in clips.items():
            emb[spk] = {"teach": np.array([embed(a, pad) for a in c["teach"]]),
                        "test": {k: np.array([embed(a, pad) for a in v]) for k, v in c["test"].items()}}
        for method in ["mean", "max", "top2"]:
            for key in sorted({k for c in clips.values() for k in c["test"]}):
                own, imp = [], []
                for spk in clips:
                    T = emb[spk]["teach"]
                    m = T.mean(0); m /= np.linalg.norm(m)
                    def score(E):
                        if method == "mean": return E @ m
                        s = np.sort(E @ T.T, axis=1)[:, ::-1]
                        return s[:, 0] if method == "max" else s[:, :2].mean(1)
                    if key in emb[spk]["test"]: own += list(score(emb[spk]["test"][key]))
                    for other in clips:
                        if other != spk and key in emb[other]["test"]:
                            imp += list(score(emb[other]["test"][key]))
                own, imp = np.array(own), np.array(imp)
                thr1 = np.quantile(imp, 0.99)
                thr01 = np.quantile(imp, 0.999)
                ths = np.linspace(-0.2, 1, 1201)
                far_ = np.array([(imp >= t).mean() for t in ths]); frr = np.array([(own < t).mean() for t in ths])
                k = np.argmin(np.abs(far_ - frr))
                results[f"{pad}/{method}/{key[0]}/{key[1]}"] = dict(
                    own_n=len(own), imp_n=len(imp),
                    own_p10=float(np.quantile(own, 0.1)), own_med=float(np.median(own)),
                    imp_p99=float(thr1), imp_p999=float(thr01), imp_max=float(imp.max()),
                    accept_035=float((own >= 0.35).mean()), false_035=float((imp >= 0.35).mean()),
                    accept_at_far1=float((own >= thr1).mean()), accept_at_far01=float((own >= thr01).mean()),
                    eer=float((far_[k] + frr[k]) / 2))
        print("done", pad, file=sys.stderr)
    json.dump(results, open(os.path.join(DATA, "voice_bench.json"), "w"), indent=1)
    for k, r in results.items():
        print(f"{k:28s} own p10 {r['own_p10']:.2f} med {r['own_med']:.2f} | imp p99 {r['imp_p99']:.2f} max {r['imp_max']:.2f}"
              f" | @0.35 own {r['accept_035']*100:5.1f}% imp {r['false_035']*100:5.2f}% | @FA1% own {r['accept_at_far1']*100:5.1f}%"
              f" | EER {r['eer']*100:4.1f}%")

if __name__ == "__main__":
    main()
