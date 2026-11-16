"""The marks of build spec section 6, as counts. Each function takes the items or pairs, the labels and the
predictions of one arm, and gives the counts and the pass result.

The marks of the spec are for the sealed sets (S1: 400 mails with 40 requests). For a set of another size, the
same shares apply: 34 of 40 is 0.85, 10 of 400 is 0.025, 28 of 40 is 0.70.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from .formats import same_sentence

D1_MAIL_FOUND = 34 / 40
D1_MAIL_FALSE = 10 / 400
D1_MAIL_SENTENCE = 28 / 40
D1_NOTE_FOUND = 0.75
D1_NOTE_FALSE_SHARE = 0.10
D2_CORRECT = 0.95
D2_COVER = 0.55
D3_CORRECT = 0.95
D3_FOUND = 0.60
D4_CORRECT = 0.90
D4_FOUND = 0.70


@dataclass
class Result:
    decision: str
    counts: dict = field(default_factory=dict)
    passed: bool | None = None

    def line(self) -> str:
        c = ", ".join(f"{k} {v}" for k, v in self.counts.items())
        p = "n/a" if self.passed is None else ("PASS" if self.passed else "FAIL")
        return f"{self.decision}: {c} -> {p}"


def apply_when_gate(item: dict, when: str) -> str:
    """Build spec 3.1: a mail gives `now` only if the owner replied to this sender before, or kept a flag of this
    sender before. A `now` for an unknown sender becomes `list`."""
    if when == "now" and item.get("kind") == "mail" and not item.get("sender_known", False):
        return "list"
    return when


def d1_mail(items, labels, preds) -> Result:
    lab = {r["id"]: r for r in labels}
    mails = [it for it in items if it["kind"] == "mail"]
    req = [it for it in mails if lab[it["id"]]["need"] == "1"]
    found = false = sentence = flags = 0
    for it in mails:
        p = preds.get(it["id"])
        if not p or p.get("need") != "1":
            continue
        flags += 1
        l = lab[it["id"]]
        if l["need"] == "1":
            found += 1
            if same_sentence(p.get("sentence", ""), l["sentence"]) or same_sentence(p.get("sentence", ""), l.get("sentence2", "")):
                sentence += 1
        else:
            false += 1
    n, r = len(mails), len(req)
    ok = (r > 0 and found >= math.ceil(D1_MAIL_FOUND * r) and false <= math.floor(D1_MAIL_FALSE * n)
          and sentence >= math.ceil(D1_MAIL_SENTENCE * r))
    return Result("D1 mail", {"mails": n, "requests": r, "flags": flags, "found": found, "false": false,
                              "sentence correct": sentence}, ok if r else None)


def d1_notes(items, labels, preds) -> Result:
    lab = {r["id"]: r for r in labels}
    notes = [it for it in items if it["kind"] == "note"]
    todo = sum(1 for it in notes if lab[it["id"]]["need"] == "1")
    flags = found = 0
    for it in notes:
        p = preds.get(it["id"])
        if p and p.get("need") == "1":
            flags += 1
            found += lab[it["id"]]["need"] == "1"
    false = flags - found
    ok = None
    if todo:
        ok = found >= D1_NOTE_FOUND * todo and (flags == 0 or false <= D1_NOTE_FALSE_SHARE * flags) and flags > 0
    return Result("D1 notes", {"notes": len(notes), "with a to-do": todo, "flags": flags, "found": found,
                               "false": false}, ok)


def d4(items, labels, preds) -> Result:
    lab = {r["id"]: r for r in labels}
    labeled = [it for it in items if lab[it["id"]].get("when")]
    true_now = sum(1 for it in labeled if lab[it["id"]]["when"] == "now")
    now = correct = 0
    for it in labeled:
        p = preds.get(it["id"])
        w = apply_when_gate(it, p.get("when", "none")) if p else "none"
        if w == "now":
            now += 1
            correct += lab[it["id"]]["when"] == "now"
    ok = None
    if true_now:
        ok = now > 0 and correct >= D4_CORRECT * now and correct >= D4_FOUND * true_now
    return Result("D4", {"labeled": len(labeled), "now labeled": true_now, "now given": now, "now correct": correct}, ok)


def pairs_mark(task: str, pairs, labels, scores: dict, threshold: float) -> Result:
    """D2 (`fit`) and D3 (`closes`). The pairs of one `group` have the same text and up to 5 candidates. The arm
    proposes the candidate with the highest score if the score is at the threshold or above. "No candidate" is a
    normal result."""
    lab = {r["id"]: r["label"] == "1" for r in labels}
    groups: dict[str, list[dict]] = {}
    for p in pairs:
        if p["task"] == task:
            groups.setdefault(p["group"], []).append(p)
    with_true = proposals = correct = 0
    for g, ps in groups.items():
        has = any(lab.get(p["id"]) for p in ps)
        with_true += has
        scored = [(scores[p["id"]], p) for p in ps if p["id"] in scores]
        if not scored:
            continue
        s, best = max(scored, key=lambda x: x[0])
        if s >= threshold:
            proposals += 1
            correct += bool(lab.get(best["id"]))
    if task == "fit":
        name, need_correct, need_found = "D2", D2_CORRECT, D2_COVER
    else:
        name, need_correct, need_found = "D3", D3_CORRECT, D3_FOUND
    ok = None
    if with_true:
        ok = proposals > 0 and correct >= need_correct * proposals and correct >= need_found * with_true
    return Result(name, {"texts": len(groups), "with a true candidate": with_true, "proposals": proposals,
                         "correct": correct}, ok)
