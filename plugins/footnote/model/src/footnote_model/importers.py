"""Converts the seen made-up sets of phase 3 to the item format of the decision model.

The sets of phase 3 have one owner (Maya Rao) and no `when` label. They are for development only (build spec 5.1).
"""

from __future__ import annotations

from pathlib import Path

from .formats import read_jsonl, read_tsv

OWNER = {"name": "Maya Rao", "address": "maya.rao@example.com"}

# Written by hand (build-a, design-a) or by the design thread (holdout2, seen since E11). Not the generator sets.
PHASE3_SETS = ("build-a", "design-a", "holdout2")


def _bulk(m: dict) -> bool:
    """Gate 1 of phase 3 (8.1), for the `sender_known` fact only. The Swift bulk filter is the real gate."""
    addrs = [a.lower() for a in m["to"] + m["cc"]]
    return (m["list_unsubscribe"] or m["precedence"].lower() in ("bulk", "list", "junk") or m["auto_submitted"]
            or m["junk"] or OWNER["address"] not in addrs or len(addrs) > 20 or m["replied"]
            or m["from_address"].lower() == OWNER["address"])


def phase3_set(folder: Path, name: str) -> tuple[list[dict], list[dict]]:
    mails = read_jsonl(Path(folder) / f"{name}.jsonl")
    labels = {r["id"]: r for r in read_tsv(Path(folder) / f"{name}-labels.tsv")}
    first: dict[str, str] = {}
    for m in mails:
        if not _bulk(m):
            a = m["from_address"].lower()
            if a not in first or m["date"] < first[a]:
                first[a] = m["date"]
    items, out_labels = [], []
    for m in mails:
        note = labels.get(m["id"], {}).get("kind", "").startswith("note") or not m["from_address"]
        it = {"id": m["id"], "kind": "note" if note else "mail", "owner": dict(OWNER), "now": m["date"], **m}
        if not note:
            it["sender_known"] = first.get(m["from_address"].lower(), m["date"]) < m["date"]
        items.append(it)
        l = labels.get(m["id"], {})
        out_labels.append({"id": m["id"], "need": l.get("request", "0"), "when": "",
                           "category": l.get("kind", ""), "sentence": l.get("sentence", ""),
                           "sentence2": l.get("sentence2", "")})
    return items, out_labels
