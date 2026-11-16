"""Diagnostic X1 (open/README.md of the design thread): a text model on an open hand-written set.

For one model run and one test file, it writes:
- the D1 mail, D1 notes and D4 lines at the dev thresholds, with and without rules gate 2;
- the false flags and the misses by label kind;
- the smallest number of false flags at 34 or more found, over all mail thresholds (this separates a ranking
  fault from a threshold fault; it is not a mark);
- a score file: id, arm, seed, request score, `now` score, held.

Usage: python -m footnote_model.x1 <run dir> <test.jsonl> <arm name> <out dir>
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from . import bench, fit, marks
from .formats import code_gate, is_note, label_file, read_jsonl, read_tsv
from .stage1 import item_preds

FOUND_LINE = 34


def gate2_ids(sw: dict[str, dict]) -> set[str]:
    return {i for i, r in sw.items() if r.get("gate", "") in bench.GATE2}


def apply_gate2(preds: dict[str, dict], held: set[str]) -> dict[str, dict]:
    return {i: ({**p, "need": "0", "when": "none"} if i in held else p) for i, p in preds.items()}


def min_false_at(res, mails, labels, held2: set[str] | None, found_line: int = FOUND_LINE):
    """The smallest number of false flags of all mail thresholds that give `found_line` or more found."""
    best = None
    for t in sorted({0.0} | {r["p_req"] for r in res.values()}):
        p = item_preds(res, mails, t, 1, 1)
        if held2 is not None:
            p = apply_gate2(p, held2)
        c = marks.d1_mail(mails, labels, bench.apply_code_gate(mails, p)).counts
        if c["found"] >= found_line and (best is None or c["false"] < best[0]):
            best = (c["false"], c["found"], t)
    return best


def run(run_dir: Path, test: Path, arm: str, out_dir: Path) -> str:
    items, labels = read_jsonl(test), read_tsv(label_file(test))
    th = json.loads((run_dir / "thresholds.json").read_text())
    seed = json.loads((run_dir / "config.json").read_text())["seed"]
    model, tok, _ = fit.load(run_dir)
    sw = bench.rules_predictions(items)
    res = fit.predict_items(model, tok, fit.item_examples(tok, items, None, sw))
    preds = item_preds(res, items, th["mail"], th["note"], th["now"])
    held2 = gate2_ids(sw)
    mails = [i for i in items if not is_note(i)]
    name = f"{test.stem} / {arm} s{seed}"
    rows, extra = [], []
    for g2 in (False, True):
        p = apply_gate2(preds, held2) if g2 else preds
        tag = name + (" +g2" if g2 else "")
        rows.append((tag, bench.score_items(items, labels, p)))
        extra.append(f"- {tag}: {bench.kind_counts(items, labels, p)}")
        m = min_false_at(res, mails, labels, held2 if g2 else None)
        extra.append(f"- {tag}: fewest false flags at {FOUND_LINE} or more found: "
                     + (f"{m[0]} (found {m[1]}, threshold {m[2]:.4f})" if m else "no threshold reaches it"))
    out_dir.mkdir(parents=True, exist_ok=True)
    with open(out_dir / f"scores-{test.stem}-{arm}-s{seed}.tsv", "w") as f:
        f.write("id\tarm\tseed\trequest_score\tnow_score\theld\n")
        for it in items:
            r = res.get(it["id"], {"p_req": 0.0, "p_now": 0.0})
            f.write(f"{it['id']}\t{arm}\t{seed}\t{r['p_req']:.4f}\t{r['p_now']:.4f}\t"
                    f"{'yes' if not is_note(it) and code_gate(it) else 'no'}\n")
    text = bench.table(rows) + "\n\n" + "\n".join(extra) + "\n"
    (out_dir / f"{test.stem}-{arm}-s{seed}.md").write_text(text)
    return text


if __name__ == "__main__":
    print(run(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4])))
