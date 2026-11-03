"""Other voices that say the owner's phrase: the template scores before the voice check.
For each voice and phrase, the owner's 5 templates against the 12 test commands of each other voice."""
import os
import pickle

import numpy as np

import qbe
from common import FRAME_S, load, template, voices
from gen import PHRASES
from paths import DATA


def best(T, frames, span):
    s, w = qbe.scores_worst(T, qbe.normalize(frames))
    order = np.argsort(s, axis=0)[:2]
    cols = np.arange(s.shape[1])
    c, wc = s[order, cols].mean(axis=0), w[order, cols].mean(axis=0)
    w0, w1 = max(0, int(span[0] / FRAME_S) - 5), int((span[1] + 1.0) / FRAME_S)
    i = w0 + int(np.argmin(c[w0:w1]))
    return float(c[i]), float(wc[i])


def main():
    vs = voices()
    out = {}
    data = {(v, p): load(v, p) for v in vs for p in PHRASES}
    for p in PHRASES:
        for v in vs:
            d = data[(v, p)]
            T = qbe.Templates([qbe.normalize(template(d["enrol"][j].astype(np.float32), d["enrol_audio"][j], delay=2))
                               for j in range(5)])
            res = []
            for ov in vs:
                if ov == v:
                    continue
                od = data[(ov, p)]
                for t, span in zip(od["test"], od["test_span"]):
                    res.append(best(T, t.astype(np.float32), span))
            out[(v, p)] = res
        print(p, flush=True)
    with open(os.path.join(DATA, "cross.pkl"), "wb") as f:
        pickle.dump(out, f)


if __name__ == "__main__":
    main()
