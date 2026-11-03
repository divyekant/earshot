"""Session check: is a short follow-up turn closer to the owner's last passed turn than to the teach profile?
Record: docs/experiments/E6-voice-check.md, section 8. Run: uv run python voice_session.py.

Live test 2026-11-03: two short go-on pieces of the owner's dictation, right after earshot typed, scored 0.23 and
0.25 against the profile and were dropped. The owner's other turns scored 0.43 to 0.73. The profile holds 5 takes
of the wake phrase only.

For each speaker, from one chapter (one recording session):
- the reference: a 7.25 s window of one file, as the turn that passed before the follow-up;
- the profile: 5 takes of 0.7 to 1.0 s from other files, as the teach step;
- the tests: windows of 1.4 s and 2.8 s from other files, as the go-on pieces.
Other voices: the tests of each other speaker against the reference and the profile of this speaker.
"""
import os, sys, numpy as np, soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_bench as vb

LENS = [1.4, 2.8]
LIMITS = [0.35, 0.40, 0.45, 0.50]

def line(seconds):
    """The app's VoiceRule: 0.35 up to 1 s of speech, then a line up to 0.42 at 2 s."""
    return 0.35 + 0.07 * min(1.0, max(0.0, seconds - 1.0))

def main():
    sp = vb.load()
    data = {}
    for spk, ch in sp.items():
        files = ch[list(ch)[0]]
        ref = None
        for i, f in enumerate(files):
            x, _ = sf.read(f, dtype="float32")
            w = vb.speech_window(x, 7.25)
            if w is not None: ref = (i, w); break
        if ref is None or len(files) < 12: continue
        rest = [f for i, f in enumerate(files) if i != ref[0]]
        teach = []
        for f in rest[-8:]:
            x, _ = sf.read(f, dtype="float32")
            w = vb.speech_window(x, vb.RNG.uniform(0.7, 1.0))
            if w is not None: teach.append(w)
            if len(teach) == 5: break
        tests = []
        for f in rest[:-8][:20]:
            x, _ = sf.read(f, dtype="float32")
            w = vb.speech_window(x, max(LENS))
            if w is not None: tests.append(w)
        row = {}
        for cond in ("near", "far"):
            tr = (lambda a: a) if cond == "near" else vb.far
            r = vb.embed(vb.trim(tr(ref[1])), "zero")
            p = np.mean([vb.embed(vb.trim(tr(t)), "zero") for t in teach], 0); p /= np.linalg.norm(p)
            t = {}
            for L in LENS:
                clips = [vb.trim(tr(a)[:int(L * vb.RATE)]) for a in tests]
                t[L] = (np.array([vb.embed(c, "zero") for c in clips]), np.array([len(c) / vb.RATE for c in clips]))
            row[cond] = (r, p, t)
        data[spk] = row
        print(spk, len(teach), len(tests), file=sys.stderr, flush=True)

    print(f"speakers {len(data)}")
    for cond in ("near", "far"):
        for L in LENS:
            own_s, own_p, own_lim, imp_s, imp_p, imp_lim = [], [], [], [], [], []
            for s, row in data.items():
                r, p, t = row[cond]
                E, sec = t[L]
                own_s += list(E @ r); own_p += list(E @ p); own_lim += [line(x) for x in sec]
                for o, orow in data.items():
                    if o == s: continue
                    Eo, seco = orow[cond][2][L]
                    imp_s += list(Eo @ r); imp_p += list(Eo @ p); imp_lim += [line(x) for x in seco]
            own_s, own_p, own_lim = map(np.array, (own_s, own_p, own_lim))
            imp_s, imp_p, imp_lim = map(np.array, (imp_s, imp_p, imp_lim))
            prof_own = own_p >= own_lim; prof_imp = imp_p >= imp_lim
            print(f"{cond} {L:.1f} s ({len(own_s)} owner, {len(imp_s)} other): "
                  f"profile score median owner {np.median(own_p):.2f}, other {np.median(imp_p):.2f}; "
                  f"session score median owner {np.median(own_s):.2f}, other {np.median(imp_s):.2f}, "
                  f"other p99 {np.quantile(imp_s, 0.99):.2f}, other max {imp_s.max():.2f}")
            print(f"  profile with the line: owner {prof_own.mean()*100:.1f}%, other {prof_imp.mean()*100:.2f}%")
            for lim in LIMITS:
                so, si = own_s >= lim, imp_s >= lim
                print(f"  session at {lim:.2f}: owner {so.mean()*100:.1f}%, other {si.mean()*100:.2f}% | "
                      f"profile or session: owner {(so | prof_own).mean()*100:.1f}%, other {(si | prof_imp).mean()*100:.2f}%")

main()
