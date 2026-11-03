"""Summarises the results of eval_voice.py: hit rate, false wakes per hour, sound-alikes, latency.

Usage: analyse.py            (the standard report)
       analyse.py sweep      (the template threshold sweep)
       analyse.py far        (the far-field check, from eval_far.py)"""
import glob
import os
import pickle
import sys

import numpy as np

from gen import PHRASES
from paths import DATA

RES = os.path.join(DATA, "results")
FAR_PATH = os.path.join(DATA, "far.pkl")
FRAME_S = 0.04


def load_all():
    out = []
    for f in sorted(glob.glob(f"{RES}/*.pkl")):
        if f.endswith(".partial.pkl"):
            continue
        with open(f, "rb") as fh:
            out.append(pickle.load(fh))
    return out


def load_cross():
    p = os.path.join(DATA, "cross.pkl")
    if os.path.exists(p):
        with open(p, "rb") as fh:
            return pickle.load(fh)
    return {}


# --- per clip decisions -----------------------------------------------------------------------
def spot_clip(dets, span):
    st, en = span
    ok = [x for x in dets if st / FRAME_S - 5 <= x <= en / FRAME_S + 25]
    return (True, (ok[0] + 1) * FRAME_S - en) if ok else (False, None)


def qbe_clip(curve, span, th, thw=None, wait=2):
    """First online detection in the window: score below th (and worst part below thw), and the score is
    not lower in the next `wait` frames. Latency = when the app knows it, after the phrase end."""
    st, en = span
    c = curve[0].astype(np.float32)
    w = curve[1].astype(np.float32)
    w0, w1 = max(0, int(st / FRAME_S) - 5), min(len(c), int((en + 1.0) / FRAME_S))
    for t in range(w0, w1):
        if c[t] < th and all(c[t] <= c[t + i] for i in range(1, wait + 1) if t + i < len(c)):
            if thw is None or w[t] < thw:
                return True, (t + wait + 1) * FRAME_S - en
    return False, None


def passes(pairs, th, thw):
    pairs = np.asarray(pairs, np.float32).reshape(-1, 2)
    ok = pairs[:, 0] < th
    if thw is not None:
        ok &= pairs[:, 1] < thw
    return int(ok.sum())


# --- one method over all voices, per phrase -----------------------------------------------------
def evaluate(results, method, th=None, thw=None, takes=5, cross=None):
    """method: 'spot', 'spot_nr', 'spot10', 'qbe', 'fusion' (spot_nr or qbe)."""
    rows = {}
    for phrase in PHRASES:
        acc = dict(hit=0, n=0, own_fa=0, own_s=0.0, lib_fa=0, lib_s=0.0, alike=0, alike_n=0, x=0, x_n=0)
        conds, lat = {}, []
        for r in results:
            p = r["phrases"].get(phrase)
            if p is None:
                continue
            q = p.get(f"qbe{takes}")
            for j, (span, cond, lead) in enumerate(zip(p["spans"], p["cond"], p["lead"])):
                if method.startswith("spot"):
                    h, l = spot_clip(p[method]["test"][j], span)
                elif method == "qbe":
                    h, l = qbe_clip(q["pos_curves"][j], span, th, thw)
                else:
                    h1, l1 = spot_clip(p["spot_nr"]["test"][j], span)
                    h2, l2 = qbe_clip(q["pos_curves"][j], span, th, thw)
                    h = h1 or h2
                    l = min(x for x in (l1, l2) if x is not None) if h else None
                acc["hit"] += h; acc["n"] += 1
                k = f"{cond}/{'talk' if lead else 'quiet'}"
                a, b = conds.get(k, (0, 0)); conds[k] = (a + h, b + 1)
                if l is not None:
                    lat.append(l)
            acc["own_s"] += r["own_seconds"]
            if method.startswith("spot"):
                m = p[method]
                acc["own_fa"] += m["own"]
                acc["alike"] += sum(m["alike"]); acc["alike_n"] += len(m["alike"])
                if "libri" in m:
                    acc["lib_fa"] += m["libri"]; acc["lib_s"] += r["spot_libri_seconds"]
            else:
                al = [passes([a], th, thw) for a in q["alike"]]
                own = passes(q["own"], th, thw)
                if method == "fusion":
                    al = [max(x, int(y)) for x, y in zip(al, p["spot_nr"]["alike"])]
                    own += p["spot_nr"]["own"]
                acc["own_fa"] += own
                acc["alike"] += sum(al); acc["alike_n"] += len(al)
                acc["lib_fa"] += passes(q["libri"], th, thw)
                acc["lib_s"] += r["libri_seconds"] if takes == 5 else r["sub_seconds"]
                if cross and (r["voice"], phrase) in cross:
                    xs = cross[(r["voice"], phrase)]
                    acc["x"] += passes(xs, th, thw); acc["x_n"] += len(xs)
        rows[phrase] = {
            "hit": acc["hit"] / max(acc["n"], 1), "n": acc["n"],
            "cond": {k: a / b for k, (a, b) in sorted(conds.items())},
            "own_fa": acc["own_fa"], "own_h": acc["own_s"] / 3600,
            "lib_fa": acc["lib_fa"], "lib_h": acc["lib_s"] / 3600,
            "alike": acc["alike"] / max(acc["alike_n"], 1),
            "cross": acc["x"] / acc["x_n"] if acc["x_n"] else None,
            "lat": float(np.median(lat)) if lat else None,
        }
    return rows


def total(rows):
    rows = {k: v for k, v in rows.items() if v["n"] > 0}
    n = sum(r["n"] for r in rows.values())
    hit = sum(r["hit"] * r["n"] for r in rows.values()) / max(n, 1)
    own_fa = sum(r["own_fa"] for r in rows.values()); own_h = sum(r["own_h"] for r in rows.values())
    lib_fa = sum(r["lib_fa"] for r in rows.values()); lib_h = sum(r["lib_h"] for r in rows.values())
    al = float(np.mean([r["alike"] for r in rows.values()]))
    xs = [r["cross"] for r in rows.values() if r["cross"] is not None]
    lat = [r["lat"] for r in rows.values() if r["lat"] is not None]
    conds = {}
    for r in rows.values():
        for k, v in r["cond"].items():
            conds.setdefault(k, []).append(v)
    return {"hit": hit, "n": n, "own_fa": own_fa, "own_h": own_h, "own_fa_h": own_fa / max(own_h, 1e-9),
            "lib_fa": lib_fa, "lib_h": lib_h, "lib_fa_h": lib_fa / max(lib_h, 1e-9) if lib_h else None,
            "alike": al, "cross": float(np.mean(xs)) if xs else None,
            "lat": float(np.median(lat)) if lat else None, "cond": {k: float(np.mean(v)) for k, v in conds.items()}}


def show(name, rows):
    print(f"\n== {name}")
    print(f"{'phrase':14} {'hit':>5} {'own fa':>7} {'own h':>6} {'other fa':>8} {'other h':>7} {'alike':>6} {'xvoice':>6} {'lat ms':>6}")
    for p, r in list(rows.items()) + [("ALL", total(rows))]:
        xv = f"{r['cross']:.2f}" if r["cross"] is not None else "-"
        la = f"{r['lat'] * 1000:.0f}" if r["lat"] is not None else "-"
        print(f"{p:14} {r['hit']:5.2f} {r['own_fa']:7d} {r['own_h']:6.2f} {r['lib_fa']:8d} {r['lib_h']:7.1f} "
              f"{r['alike']:6.2f} {xv:>6} {la:>6}")


def far_report():
    """Hit rate on the far-field commands: the spotter (no reset) and the templates at some limits."""
    p = FAR_PATH
    with open(p, "rb") as fh:
        far = pickle.load(fh)
    clips = [(d, j, s) for d in far.values() for j, s in enumerate(d["spans"])]
    n = len(clips)
    spot = sum(spot_clip(d["spot_nr"][j], s)[0] for d, j, s in clips)
    print(f"far field, {n} commands: spot_nr {spot / n:.3f}")
    for th, thw in ((0.30, None), (0.33, None), (0.36, None), (0.40, None), (0.33, 0.5)):
        h = sum(qbe_clip(d["curves"][j], s, th, thw)[0] for d, j, s in clips)
        print(f"  qbe th {th:.2f} worst {thw}: {h / n:.3f}")


if __name__ == "__main__":
    res = load_all()
    cross = load_cross()
    print("voices:", [r["voice"] for r in res])
    if len(sys.argv) > 1 and sys.argv[1] == "far":
        far_report()
        sys.exit()
    if len(sys.argv) > 1 and sys.argv[1] == "sweep":
        for thw in (None, 0.5, 0.45, 0.4):
            for th in (0.24, 0.27, 0.30, 0.33, 0.36, 0.40):
                t = total(evaluate(res, "qbe", th, thw, cross=cross))
                print(f"th {th:.2f} worst {thw}: hit {t['hit']:.3f} own {t['own_fa']}/{t['own_h']:.1f}h "
                      f"other {t['lib_fa']}/{t['lib_h']:.0f}h alike {t['alike']:.2f} xvoice {t['cross']}")
        sys.exit()
    for m in ("spot", "spot_nr", "spot10"):
        show(m, evaluate(res, m))
    for th, thw in ((0.30, None), (0.33, None), (0.30, 0.45), (0.33, 0.45)):
        show(f"qbe th {th} worst {thw}", evaluate(res, "qbe", th, thw, cross=cross))
    show("fusion spot_nr + qbe 0.30/0.45", evaluate(res, "fusion", 0.30, 0.45))
