"""Converts the seen made-up sets of phase 3 to the item format of the decision model (RULE-need.md).

The sets of phase 3 have one owner (Maya Rao) and no D4 label: a request becomes `list`. They are for
development only (build spec 5.1).
"""

from __future__ import annotations

from pathlib import Path

from .formats import read_jsonl, read_tsv

OWNER = {"name": "Maya Rao", "address": "maya.rao@example.com"}

# Written by hand (build-a, design-a) or by the design thread (holdout2, seen since E11). Not the generator sets.
PHASE3_SETS = ("build-a", "design-a", "holdout2")


def phase3_set(folder: Path, name: str) -> tuple[list[dict], list[dict]]:
    mails = read_jsonl(Path(folder) / f"{name}.jsonl")
    labels = {r["id"]: r for r in read_tsv(Path(folder) / f"{name}-labels.tsv")}
    items = [{"id": m["id"], "owner": dict(OWNER), "now": m["date"], **m} for m in mails]
    out_labels = []
    for m in mails:
        l = labels.get(m["id"], {})
        out_labels.append({"id": m["id"], "need": "list" if l.get("request") == "1" else "none",
                           "kind": l.get("kind", ""), "sentence": l.get("sentence", ""),
                           "sentence2": l.get("sentence2", "")})
    return items, out_labels
