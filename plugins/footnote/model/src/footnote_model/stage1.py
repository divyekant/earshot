"""Stage 1 driver (build spec 4.2): fit one open encoder on the fit data, select the thresholds on dev, and write
the dev table. `uv run --group fit python -m footnote_model.stage1 <base> <out dir> [--epochs N] [--no-pairs]`.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from . import bench, fit, marks
from .formats import code_gate, is_note, pair_group, read_jsonl, read_tsv

DATA = bench.MODEL_DIR / "data"


def load_items(name):
    return read_jsonl(DATA / f"{name}.jsonl.gz"), read_tsv(DATA / f"{name}-labels.tsv")


def load_pairs(task, name):
    p = DATA / f"{task}-{name}.jsonl.gz"
    if not p.exists():
        return [], []
    return read_jsonl(p), read_tsv(DATA / f"{task}-{name}-labels.tsv")


def item_preds(res, items, t_mail, t_note, t_now):
    out = {}
    for it in items:
        r = res.get(it["id"], {"p_req": 0, "p_now": 0, "best": ""})
        t = t_note if is_note(it) else t_mail
        need = r["p_req"] >= t and not code_gate(it)
        when = ("now" if r["p_now"] >= t_now else "list") if need else "none"
        out[it["id"]] = {"need": "1" if need else "0", "when": when, "sentence": r["best"], "need_score": r["p_req"]}
    return out


GRID = [i / 100 for i in range(2, 99)]


def select_item_thresholds(res, items, labels):
    mails = [i for i in items if not is_note(i)]
    notes = [i for i in items if is_note(i)]
    # Design thread, 2026-11-16: false flags first, found second. Of the thresholds that reach the found mark, the
    # one with the fewest false flags. If none reaches it: the most found within the false mark.
    req = sum(1 for i in mails if marks.is_request({r["id"]: r for r in labels}[i["id"]]))
    cands = []
    for t in GRID:
        c = marks.d1_mail(mails, labels, item_preds(res, mails, t, 1, 1)).counts
        if c["false"] <= marks.D1_MAIL_FALSE * len(mails):
            cands.append((c["found"] >= marks.D1_MAIL_FOUND * req, -c["false"], c["found"], t))
    reach = [x for x in cands if x[0]]
    if reach:
        best_m = (0, max(reach, key=lambda x: (x[1], x[2], x[3]))[3])
    elif cands:
        best_m = (0, max(cands, key=lambda x: (x[2], x[1], x[3]))[3])
    else:
        best_m = (0, 0.98)
    best_n = (-1, 0.5)
    for t in GRID:
        r = marks.d1_notes(notes, labels, item_preds(res, notes, 1, t, 1))
        c = r.counts
        if c["flags"] and c["false"] <= marks.D1_NOTE_FALSE_SHARE * c["flags"] and c["found"] >= best_n[0]:
            best_n = (c["found"], t)
    best_w = (-1, 0.99)
    for t in GRID:
        r = marks.d4(items, labels, item_preds(res, items, best_m[1], best_n[1], t))
        c = r.counts
        if c["now given"] and c["now correct"] >= marks.D4_CORRECT * c["now given"] and c["found"] >= best_w[0]:
            best_w = (c["found"], t)
    return {"mail": best_m[1], "note": best_n[1], "now": best_w[1]}


def select_pair_threshold(task, pairs, labels, scores):
    need = marks.D2_CORRECT if task == "fit" else marks.D3_CORRECT
    best = (-1, 0.99)
    for t in GRID:
        r = marks.pairs_mark(task, pairs, labels, scores, t)
        c = r.counts
        if c["proposals"] and c["correct"] >= need * c["proposals"] and c["correct"] >= best[0]:
            best = (c["correct"], t)
    return best[1]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("out")
    ap.add_argument("--epochs", type=int, default=4)
    ap.add_argument("--lr", type=float, default=5e-5)
    ap.add_argument("--no-pairs", action="store_true")
    a = ap.parse_args(argv)
    out = Path(a.out)
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(a.base)
    fi, fl = load_items("items-fit")
    di, dl = load_items("items-dev")
    sw = bench.rules_predictions(fi + di)
    ie = fit.item_examples(tok, fi, fl, sw)
    pe, dev_pairs = [], {}
    if not a.no_pairs:
        for task, prefix in (("fit", "fit"), ("closes", "close")):
            tp, tl = load_pairs(prefix, "train")
            pe += fit.pair_examples(tok, tp, tl, task)
            dev_pairs[task] = load_pairs(prefix, "dev")
    t0 = time.time()
    model, tok = fit.train(a.base, ie, pe, out, epochs=a.epochs, lr=a.lr)
    fit_s = time.time() - t0
    res = fit.predict_items(model, tok, fit.item_examples(tok, di, None, sw))
    th = select_item_thresholds(res, di, dl)
    preds = item_preds(res, di, th["mail"], th["note"], th["now"])
    with open(out / "pred-items-dev.tsv", "w") as f:
        f.write("id\tneed\tneed_score\twhen\tsentence\n")
        for i, p in preds.items():
            f.write(f"{i}\t{p['need']}\t{p['need_score']:.4f}\t{p['when']}\t{p['sentence']}\n")
    rows = [(f"items-dev / {a.base}", bench.score_items(di, dl, preds))]
    for task, (pp, pl) in dev_pairs.items():
        if not pp:
            continue
        sc = fit.predict_pairs(model, tok, fit.pair_examples(tok, pp, None, task))
        th[task] = select_pair_threshold(task, pp, pl, sc)
        for kind in ("project", "item"):
            sub = [p for p in pp if p["b"]["kind"] == kind]
            if sub:
                r = marks.pairs_mark(task, sub, pl, sc, th[task])
                r.decision += f" ({kind})"
                rows.append((f"{task}-dev / {a.base}", [r]))
    text = bench.table(rows)
    (out / "thresholds.json").write_text(json.dumps(th))
    (out / "dev.md").write_text(f"fit {fit_s:.0f} s, thresholds {th}\n\n{text}\n")
    print(f"fit {fit_s:.0f} s, thresholds {th}")
    print(text)


if __name__ == "__main__":
    main()
