"""Stage 1 driver (build spec 4.2): fit one open encoder on the fit data, select the thresholds on dev, and write
the dev table. `uv run --group fit python -m footnote_model.stage1 <base> <out dir> [--epochs N] [--no-pairs]`.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from . import bench, control, fit, marks
from .formats import code_gate, is_note, pair_group, read_jsonl, read_tsv

DATA = bench.MODEL_DIR / "data"


def load_items(name):
    return read_jsonl(DATA / f"{name}.jsonl.gz"), read_tsv(DATA / f"{name}-labels.tsv")


def load_rounds(load, *args):
    """Round 1 file and the files of later rounds (name + "2", name + "3"), joined. Round 3 has fit files only."""
    a, b = load(*args)
    for r in ("2", "3"):
        p = DATA / (f"{args[0]}-{args[1]}{r}.jsonl.gz" if len(args) == 2 else f"{args[0]}{r}.jsonl.gz")
        if p.exists():
            a2, b2 = load(*args[:-1], args[-1] + r)
            a, b = a + a2, b + b2
    return a, b


def short_note_dev(items, labels):
    """Round 3 has short notes for the owner's own eyes (design thread, 2026-11-16). The notes of the last owner by
    name of each round 3 writer are a dev set for the note threshold only; they leave the fit data."""
    r3 = {i["id"] for i in (load_items("items-fit3")[0] if (DATA / "items-fit3.jsonl.gz").exists() else [])}
    by_writer = {}
    for it in items:
        if it["id"] in r3:
            by_writer.setdefault(it["id"].split("-")[0], set()).add(it["owner"]["name"])
    held = {w: max(o) for w, o in by_writer.items()}
    dev_ids = {it["id"] for it in items if it["id"] in r3 and is_note(it) and it["owner"]["name"] == held[it["id"].split("-")[0]]}
    keep = lambda xs: [x for x in xs if x["id"] not in dev_ids]
    take = lambda xs: [x for x in xs if x["id"] in dev_ids]
    return keep(items), keep(labels), take(items), take(labels)


def round2_ids(name):
    p = DATA / f"{name}2.jsonl.gz"
    return {x["id"] for x in read_jsonl(p)} if p.exists() else set()


def splits(ids2):
    """(name suffix, keep) for all dev, and for dev1 and dev2 when round 2 is there."""
    out = [(" (all)" if ids2 else "", lambda i: True)]
    if ids2:
        out += [("1", lambda i: i not in ids2), ("2", lambda i: i in ids2)]
    return out


def item_rows(arm, di, dl, preds):
    rows = []
    nd = [i for i in di if i["id"].startswith("x")]
    if nd:
        rows.append((f"short-notes-dev3 / {arm}", bench.score_items(nd, dl, {k: v for k, v in preds.items() if k.startswith("x")})))
        di = [i for i in di if not i["id"].startswith("x")]
    for sfx, keep in splits(round2_ids("items-dev")):
        sub = [i for i in di if keep(i["id"])]
        rows.append((f"items-dev{sfx} / {arm}", bench.score_items(sub, dl, {k: v for k, v in preds.items() if keep(k)})))
    return rows


def pair_rows(arm, task, pp, pl, sc, threshold):
    rows = []
    prefix = "fit" if task == "fit" else "close"
    for sfx, keep in splits(round2_ids(f"{prefix}-dev")):
        for kind in ("project", "item"):
            sub = [p for p in pp if p["b"]["kind"] == kind and keep(p["id"])]
            if sub:
                r = marks.pairs_mark(task, sub, pl, sc, threshold)
                r.decision += f" ({kind})"
                rows.append((f"{task}-dev{sfx} / {arm}", [r]))
    return rows


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
    """The fixed grid stops at 0.98, and a fit head can give scores above it. So the candidates are the grid and
    every score that a dev pair has: a threshold between two scores gives the same result as the higher score."""
    need = marks.D2_CORRECT if task == "fit" else marks.D3_CORRECT
    best = (-1, 1.01)
    for t in sorted(set(GRID) | {float(v) for v in scores.values()}):
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
    ap.add_argument("--no-items", action="store_true", help="pair model only (two-model arm)")
    ap.add_argument("--seed", type=int, default=13)
    ap.add_argument("--eg", help="give the pair heads the EmbeddingGemma pair features; the value is a cache file")
    a = ap.parse_args(argv)
    out = Path(a.out)
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(a.base)
    fi, fl = load_rounds(load_items, "items-fit")
    di, dl = load_rounds(load_items, "items-dev")
    fi, fl, ni, nl = short_note_dev(fi, fl)
    di, dl = di + ni, dl + nl
    if a.no_items:
        fi, fl = [], []
    sw = bench.rules_predictions(fi + di)
    ie = fit.item_examples(tok, fi, fl, sw)
    pe, dev_pairs, feats = [], {}, {}
    if not a.no_pairs:
        for task, prefix in (("fit", "fit"), ("closes", "close")):
            tp, tl = load_rounds(load_pairs, prefix, "train")
            dev_pairs[task] = load_rounds(load_pairs, prefix, "dev")
            if a.eg:
                feats.update(control.pair_feature_map(tp + dev_pairs[task][0], a.eg))
            pe += fit.pair_examples(tok, tp, tl, task, feats)
    t0 = time.time()
    model, tok = fit.train(a.base, ie, pe, out, epochs=a.epochs, lr=a.lr, seed=a.seed,
                           extra=len(next(iter(feats.values()))) if feats else 0)
    fit_s = time.time() - t0
    res = fit.predict_items(model, tok, fit.item_examples(tok, di, None, sw))
    th = select_item_thresholds(res, di, dl)
    preds = item_preds(res, di, th["mail"], th["note"], th["now"])
    with open(out / "pred-items-dev.tsv", "w") as f:
        f.write("id\tneed\tneed_score\twhen\tsentence\n")
        for i, p in preds.items():
            f.write(f"{i}\t{p['need']}\t{p['need_score']:.4f}\t{p['when']}\t{p['sentence']}\n")
    rows = item_rows(a.base, di, dl, preds)
    for task, (pp, pl) in dev_pairs.items():
        if not pp:
            continue
        sc = fit.predict_pairs(model, tok, fit.pair_examples(tok, pp, None, task, feats))
        (out / f"pair-scores-{task}-dev.json").write_text(json.dumps(sc))
        th[task] = select_pair_threshold(task, pp, pl, sc)
        rows += pair_rows(a.base, task, pp, pl, sc, th[task])
    text = bench.table(rows)
    (out / "thresholds.json").write_text(json.dumps(th))
    (out / "dev.md").write_text(f"fit {fit_s:.0f} s, thresholds {th}\n\n{text}\n")
    print(f"fit {fit_s:.0f} s, thresholds {th}")
    print(text)


if __name__ == "__main__":
    main()
