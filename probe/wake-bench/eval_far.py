"""Far-field check: the spotter (fixed reset) and the audio templates on the far-field test commands.
Teach takes are the near ones. Usage: eval_far.py (all voices with far data)."""
import os
import pickle

import numpy as np
import sentencepiece as spm

import kws
import kwsdec
import qbe
from common import FRAME_S, load, template, voices, GEN
from eval_voice import spot_specs, run_spot
from gen import PHRASES
from paths import DATA


def main():
    k = kws.Kws()
    sp = spm.SentencePieceProcessor(model_file=f"{kws.KWS_DIR}/bpe.model")
    W, b = kwsdec.joiner_weights()
    out = {}
    for v in voices():
        for phrase in PHRASES:
            f = f"{GEN}/{v}/{phrase.replace(' ', '_')}_far.npz"
            if not os.path.exists(f):
                continue
            far = np.load(f, allow_pickle=True)
            d = load(v, phrase)
            enrol = [e.astype(np.float32) for e in d["enrol"]]
            specs, _, _ = spot_specs(k, sp, phrase, enrol[:5], W, b)
            dec = kwsdec.KwsDecoder(k, kwsdec.graph_for(k, specs), W=W, b=b, auto_reset_s=1e9)
            T = qbe.Templates([qbe.normalize(template(enrol[j], d["enrol_audio"][j], delay=2)) for j in range(5)])
            spot, curves = [], []
            for t in far["test"]:
                t = t.astype(np.float32)
                spot.append(run_spot(dec, t))
                s, w = qbe.scores_worst(T, qbe.normalize(t))
                order = np.argsort(s, axis=0)[:2]
                cols = np.arange(s.shape[1])
                curves.append(np.stack([s[order, cols].mean(axis=0), w[order, cols].mean(axis=0)]).astype(np.float16))
            out[(v, phrase)] = {"spans": far["test_span"], "spot_nr": spot, "curves": curves}
        print(v, flush=True)
    with open(os.path.join(DATA, "far.pkl"), "wb") as fh:
        pickle.dump(out, fh)


if __name__ == "__main__":
    main()
