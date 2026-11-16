"""The control arm on dev (build spec 6): logistic scores on EmbeddingGemma numbers, no new model.
`uv run python -m footnote_model.control_run <out dir>`. Needs `llama-server --embedding` at EMBED_URL."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

from . import bench, control, marks
from .formats import is_note
from .stage1 import (short_note_dev, item_preds, item_rows, load_items, load_pairs, load_rounds, pair_rows, select_item_thresholds,
                     select_pair_threshold)

NEED = ("none", "list", "now")


class ControlArm:
    def fit(self, items, labels, sw, pair_sets):
        self.pair = {}
        if not items:
            return self._fit_pairs(pair_sets)
        lab = {r["id"]: r for r in labels}
        x = self._item_x(items, sw)
        y_req = np.array([lab[i["id"]]["need"] != "none" for i in items], float)
        y_now = np.array([lab[i["id"]]["need"] == "now" for i in items], float)
        self.req = control.Logistic(lam=0.001, steps=800, lr=1.0).fit(x, y_req, weight_pos=3)
        self.now = control.Logistic(lam=0.001, steps=800, lr=1.0).fit(x, y_now, weight_pos=8)
        return self._fit_pairs(pair_sets)

    def _fit_pairs(self, pair_sets):
        for task, (pp, pl) in pair_sets.items():
            if pp:
                pl = {r["id"]: float(r["label"]) for r in pl}
                self.pair[task] = control.Logistic(lam=0.0, steps=800, lr=1.0).fit(
                    control.pair_features(pp), np.array([pl[p["id"]] for p in pp]))
        return self

    @staticmethod
    def _item_x(items, sw):
        texts = [control.item_text(it, sw[it["id"]].get("sentences", "")) for it in items]
        v = control.embed(texts, control.PASSAGE)
        note = np.array([[1.0 if is_note(it) else 0.0] for it in items])
        return np.hstack([v, note])

    def item_res(self, items, sw):
        x = self._item_x(items, sw)
        pr, pn = self.req.p(x), self.now.p(x)
        # The control has no sentence head: it shows the best sentence of the rules arm, else the first sentence.
        def best(it):
            r = sw[it["id"]]
            return r.get("sentence") or next((t for t in r.get("sentences", "").split("\x1e") if t.strip()), "")
        return {it["id"]: {"p_req": float(pr[k]), "p_now": float(pn[k]), "best": best(it)} for k, it in enumerate(items)}

    def pair_scores(self, task, pairs):
        s = self.pair[task].p(control.pair_features(pairs))
        return {p["id"]: float(s[k]) for k, p in enumerate(pairs)}


def main():
    out = Path(sys.argv[1])
    pairs_only = "--pairs-only" in sys.argv
    out.mkdir(parents=True, exist_ok=True)
    fi, fl = load_rounds(load_items, "items-fit")
    di, dl = load_rounds(load_items, "items-dev")
    fi, fl, ni, nl = short_note_dev(fi, fl)
    di, dl = di + ni, dl + nl
    if pairs_only:
        fi, fl, di, dl = [], [], [], []
    sw = bench.rules_predictions(fi + di) if fi else {}
    pair_fit = {"fit": load_rounds(load_pairs, "fit", "train"), "closes": load_rounds(load_pairs, "close", "train")}
    arm = ControlArm().fit(fi, fl, sw, pair_fit)
    th, rows = {}, []
    if not pairs_only:
        res = arm.item_res(di, sw)
        th = select_item_thresholds(res, di, dl)
        rows = item_rows("control", di, dl, item_preds(res, di, th["mail"], th["note"], th["now"]))
    for task, prefix in (("fit", "fit"), ("closes", "close")):
        pp, pl = load_rounds(load_pairs, prefix, "dev")
        if not pp or task not in arm.pair:
            continue
        sc = arm.pair_scores(task, pp)
        (out / f"pair-scores-{task}-dev.json").write_text(json.dumps(sc))
        th[task] = select_pair_threshold(task, pp, pl, sc)
        rows += pair_rows("control", task, pp, pl, sc, th[task])
    text = bench.table(rows)
    (out / "dev.md").write_text(f"thresholds {th}\n\n{text}\n")
    (out / "thresholds.json").write_text(json.dumps(th))
    print(f"thresholds {th}")
    print(text)


if __name__ == "__main__":
    main()
