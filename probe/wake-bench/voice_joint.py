"""Joint check: the phrase alone as a first gate, then the whole turn (phrase + command) as the decision.
Record: docs/experiments/E6-voice-check.md. Run: uv run python voice_joint.py."""
import os, sys, json, numpy as np, soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_bench as vb

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
            w = vb.speech_window(x, 2.5)
            if w is None: continue
            for cond, a in (("near", w), ("far", vb.far(w))):
                ph = vb.embed(vb.trim(a[:int(0.8 * vb.RATE)]), "zero")
                tu = vb.embed(vb.trim(a), "zero")
                rows.append((cond, ph, tu))
        trials[spk] = rows
        print(spk, len(rows), file=sys.stderr)
    out = {}
    for cond in ("near", "far"):
        own, imp = [], []
        for spk in sp:
            for c, ph, tu in trials[spk]:
                if c == cond: own.append((ph @ prof[spk], tu @ prof[spk]))
            for o in sp:
                if o == spk: continue
                for c, ph, tu in trials[o]:
                    if c == cond: imp.append((ph @ prof[spk], tu @ prof[spk]))
        own, imp = np.array(own), np.array(imp)
        print(f"\n{cond}: owner {len(own)}, others {len(imp)}")
        print("phrase only (today):", " ".join(f"@{t:.2f} own {np.mean(own[:,0]>=t)*100:.0f}% imp {np.mean(imp[:,0]>=t)*100:.2f}%" for t in (0.30, 0.35)))
        print("turn only:          ", " ".join(f"@{t:.2f} own {np.mean(own[:,1]>=t)*100:.0f}% imp {np.mean(imp[:,1]>=t)*100:.2f}%" for t in (0.35, 0.38, 0.40, 0.42, 0.45)))
        for g in (0.0, 0.10, 0.15, 0.20):
            print(f"gate {g:.2f}: speech starts for own {np.mean(own[:,0]>=g)*100:.0f}% imp {np.mean(imp[:,0]>=g)*100:.1f}% |",
                  " ".join(f"turn@{t:.2f} own {np.mean((own[:,0]>=g)&(own[:,1]>=t))*100:.0f}% imp {np.mean((imp[:,0]>=g)&(imp[:,1]>=t))*100:.2f}%" for t in (0.35, 0.40, 0.42)))
        print("imp turn p99 %.2f p99.9 %.2f max %.2f; own turn p10 %.2f med %.2f; own phrase p10 %.2f med %.2f" % (
            np.quantile(imp[:,1], .99), np.quantile(imp[:,1], .999), imp[:,1].max(), np.quantile(own[:,1], .1), np.median(own[:,1]),
            np.quantile(own[:,0], .1), np.median(own[:,0])))
main()
