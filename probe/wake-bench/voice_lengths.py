"""Length sweep: at which speech length does the turn limit 0.42 pass the owner as often as 0.35 does?
Record: docs/experiments/E6-voice-check.md. Run: uv run python voice_lengths.py."""
import os, sys, numpy as np, soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_bench as vb

LENS = [0.8, 1.0, 1.2, 1.6, 2.0]
def main():
    sp = vb.load()
    prof, trials = {}, {}
    for spk, ch in sp.items():
        names = list(ch)
        teach = []
        for f in ch[names[0]][:8]:
            x, _ = sf.read(f, dtype="float32")
            w = vb.speech_window(x, vb.RNG.uniform(0.7, 1.0))
            if w is not None: teach.append(vb.embed(vb.trim(w), "zero"))
            if len(teach) == 5: break
        m = np.mean(teach, 0); prof[spk] = m / np.linalg.norm(m)
        other = [f for c in names[1:] for f in ch[c]]
        if len(other) < 10: other = ch[names[0]][8:]
        rows = []
        for f in other[:24]:
            x, _ = sf.read(f, dtype="float32")
            w = vb.speech_window(x, max(LENS))
            if w is None: continue
            for cond, a in (("near", w), ("far", vb.far(w))):
                rows.append((cond, [vb.embed(vb.trim(a[:int(L * vb.RATE)]), "zero") for L in LENS]))
        trials[spk] = rows
        print(spk, len(rows), file=sys.stderr, flush=True)
    for cond in ("near", "far"):
        for i, L in enumerate(LENS):
            own = np.array([e[i] @ prof[s] for s in sp for c, e in trials[s] if c == cond])
            imp = np.array([e[i] @ prof[s] for s in sp for o in sp if o != s for c, e in trials[o] if c == cond])
            print(f"{cond} {L:.1f} s: " + " ".join(f"@{t:.2f} own {np.mean(own>=t)*100:.0f}% imp {np.mean(imp>=t)*100:.2f}%" for t in (0.35, 0.38, 0.42)), flush=True)
main()
