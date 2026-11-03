"""Runs every method on the data of one voice and saves the raw results for analyse.py.

Methods:
- spot:     the shipped method. Spelled pieces (boost 1.0, threshold 0.25), plus the pieces heard in the
            enrolment takes if the spelled pieces fire on fewer than n-1 takes (boost 1.5, threshold 0.2).
            Beam 4, 1 trailing blank, search reset every 1.5 s (as StreamingKwsDecoder.swift).
- spot_nr:  the same, with no 1.5 s reset (the reset bug fixed).
- spot10:   spot_nr with 10 enrolment takes.
- qbe:      audio templates (5 takes), streaming DTW on the spotter's encoder frames. Scores are kept, so
            analyse.py can set any threshold.
Usage: eval_voice.py <voice> [libri_hours_for_spot]"""
import os
import pickle
import sys
import time

import numpy as np
import sentencepiece as spm

import kws
import kwsdec
import qbe
from common import FRAME_S, libri, load, nms_idx, own, template, voices
from gen import PHRASES
from paths import DATA

OUT = os.path.join(DATA, "results")
BANK_CHAPTERS = 10  # the first chapters of test-other: the calibration bank, not test data


def split_libri():
    names = [n for n, _ in ((n, None) for n in sorted(os.listdir(os.path.join(DATA, "libri_frames"))))]
    names = [n[:-4] for n in names if n.endswith(".npy")]
    other = [n for n in names if n.startswith("test-other")]
    bank = set(other[:BANK_CHAPTERS])
    return bank


def spot_specs(k, sp, phrase, enrol_frames, W, b):
    """The keyword list of the shipped app for one enrolment (WakeModels.enrol + keywords)."""
    spelled = sp.encode(phrase.upper(), out_type=str)
    g = kwsdec.graph_for(k, [(spelled, 1.0, 0.25, phrase)])
    dec = kwsdec.KwsDecoder(k, g, W=W, b=b, auto_reset_s=1e9)
    hits, learned = 0, []
    for fr in enrol_frames:
        dec.reset()
        if dec.run(fr):
            hits += 1
        pieces = k.greedy(fr)
        if 3 <= len(pieces) <= len(spelled) + 6 and pieces != spelled and pieces not in learned:
            learned.append(pieces)
    keep = [] if hits >= len(enrol_frames) - 1 else learned
    specs = [(spelled, 1.0, 0.25, phrase)] + [(p, 1.5, 0.2, phrase) for p in keep]
    return specs, hits, learned


def run_spot(dec, frames):
    dec.reset()
    return [h[0] for h in dec.run(frames)]


def main():
    voice = sys.argv[1]
    spot_libri_h = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
    os.makedirs(OUT, exist_ok=True)
    k = kws.Kws()
    sp = spm.SentencePieceProcessor(model_file=f"{kws.KWS_DIR}/bpe.model")
    W, b = kwsdec.joiner_weights()
    bank_names = split_libri()
    lib = list(libri())
    lib_norm = [(n, f) for n, f in lib]
    sub, tot3 = set(), 0.0
    for n, f in lib:
        if n not in bank_names and tot3 < 3 * 3600:
            sub.add(n)
            tot3 += len(f) * FRAME_S
    own_f, own_s = own(voice)
    own_n = qbe.normalize(own_f)
    # spot on Libri: a fixed subset of test chapters, about spot_libri_h hours
    spot_lib, tot = [], 0.0
    for n, f in lib:
        if n in bank_names:
            continue
        if tot >= spot_libri_h * 3600:
            break
        spot_lib.append(f)
        tot += len(f) * FRAME_S
    others = [v for v in voices() if v != voice]
    res = {"voice": voice, "sub_seconds": tot3, "own_seconds": own_s, "spot_libri_seconds": tot,
           "libri_seconds": sum(len(f) for n, f in lib if n not in bank_names) * FRAME_S,
           "bank_seconds": sum(len(f) for n, f in lib if n in bank_names) * FRAME_S, "phrases": {}}
    del lib
    only = os.environ.get("PHRASES")
    part = f"{OUT}/{voice}.partial.pkl"
    if os.path.exists(part):
        with open(part, "rb") as f:
            res["phrases"] = pickle.load(f)
    for phrase in PHRASES:
        if only and phrase not in only.split(","):
            continue
        if phrase in res["phrases"]:
            continue
        t0 = time.time()
        d = load(voice, phrase)
        enrol = [e.astype(np.float32) for e in d["enrol"]]
        audio = list(d["enrol_audio"])
        tests = [t.astype(np.float32) for t in d["test"]]
        spans = d["test_span"]
        alike = [a.astype(np.float32) for a in d["alike"]]
        r = {"spans": spans, "cond": d["test_cond"], "lead": d["test_lead"]}

        # --- the shipped spotter and its variants ---
        for name, n_takes, reset in [("spot", 5, 1.5), ("spot_nr", 5, 1e9), ("spot10", 10, 1e9)]:
            specs, hits, learned = spot_specs(k, sp, phrase, enrol[:n_takes], W, b)
            g = kwsdec.graph_for(k, specs)
            dec = kwsdec.KwsDecoder(k, g, W=W, b=b, auto_reset_s=reset)
            m = {"specs": specs, "enrol_hits": hits, "heard": learned,
                 "test": [run_spot(dec, t) for t in tests],
                 "own": len(run_spot(dec, own_f)),
                 "alike": [len(run_spot(dec, a)) > 0 for a in alike]}
            if name != "spot":
                m["libri"] = sum(len(run_spot(dec, f)) for f in spot_lib)
            r[name] = m

        # --- audio templates ---
        def curves(T, frames):
            """Per frame: the score (mean of the 2 best templates) and their worst-part score."""
            s, w = qbe.scores_worst(T, qbe.normalize(frames))
            order = np.argsort(s, axis=0)[:2]
            cols = np.arange(s.shape[1])
            return s[order, cols].mean(axis=0), w[order, cols].mean(axis=0)

        def minima(T, frames):
            c, w = curves(T, frames)
            i = nms_idx(c)
            return np.stack([c[i], w[i]], axis=1).astype(np.float32) if len(i) else np.zeros((0, 2), np.float32)

        def best(T, frames, span=None):
            c, w = curves(T, frames)
            if span is not None:
                w0, w1 = max(0, int(span[0] / FRAME_S) - 5), int((span[1] + 1.0) / FRAME_S)
                m = np.full_like(c, np.inf); m[w0:w1] = c[w0:w1]; c2 = m
            else:
                c2 = c
            i = int(np.argmin(c2))
            return float(c[i]), float(w[i])

        for n_takes in (3, 5, 10):
            tmpl = [qbe.normalize(template(enrol[j], audio[j], delay=2)) for j in range(n_takes)]
            T = qbe.Templates(tmpl)
            q = {"lens": T.lens.tolist(), "pos_curves": []}
            for t in tests:
                c, w = curves(T, t)
                q["pos_curves"].append(np.stack([c, w]).astype(np.float16))
            q["own"] = minima(T, own_f)
            q["alike"] = [best(T, a) for a in alike]
            lm, bm = [], []
            for n, f in lib_norm:
                if n_takes != 5 and n not in bank_names and n not in sub:
                    continue
                (bm if n in bank_names else lm).append(minima(T, f))
            q["libri"] = np.concatenate(lm)
            q["bank"] = np.concatenate(bm)
            # leave-one-out scores of the takes (what the app can see at enrolment)
            q["loo"] = [best(qbe.Templates([x for i, x in enumerate(tmpl) if i != j]), enrol[j])
                        for j in range(n_takes)]
            if n_takes == 5 and not os.environ.get("NOCROSS"):
                cross = []
                for ov in others:
                    try:
                        od = load(ov, phrase)
                    except FileNotFoundError:
                        continue
                    for t, span in zip(od["test"], od["test_span"]):
                        cross.append(best(T, t.astype(np.float32), span))
                q["cross"] = cross
            r[f"qbe{n_takes}"] = q
        res["phrases"][phrase] = r
        with open(part + ".tmp", "wb") as f:
            pickle.dump(res["phrases"], f)
        os.replace(part + ".tmp", part)
        print(voice, phrase, f"{time.time() - t0:.0f}s", flush=True)
    with open(f"{OUT}/{voice}.pkl.tmp", "wb") as f:
        pickle.dump(res, f)
    os.replace(f"{OUT}/{voice}.pkl.tmp", f"{OUT}/{voice}.pkl")


if __name__ == "__main__":
    main()
