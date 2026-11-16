"""The data formats of the decision model (README.md, section "Formats").

Item file: JSON lines, one mail or note for each line, plain or gzip (`.jsonl.gz`).
Pair file: JSON lines, one text and one candidate for each line.
Label file: TSV with a header row, beside the data file (`<name>-labels.tsv`).
"""

from __future__ import annotations

import gzip
import json
import re
from pathlib import Path

ITEM_FIELDS = ("id", "owner", "now", "from_name", "from_address", "to", "cc", "subject", "date",
               "list_unsubscribe", "precedence", "auto_submitted", "junk", "replied", "body")
# The label formats of the rule files of the design thread (RULE-need.md, RULE-when.md, RULE-pair.md).
NEED_LABEL_COLUMNS = ("id", "need", "kind", "sentence", "sentence2")
PAIR_LABEL_COLUMNS = ("id", "label", "kind")
NEED_VALUES = ("none", "list", "now")
PAIR_TASKS = ("fit", "closes")


def is_request(label: dict) -> bool:
    """D1: `list` and `now` are both a request (RULE-need.md)."""
    return label.get("need") in ("list", "now")


def pair_task(path: Path) -> str:
    """RULE-pair.md: D2 files start with `fit-`, D3 files start with `close-`."""
    name = Path(path).name
    if name.startswith("fit-"):
        return "fit"
    if name.startswith("close-"):
        return "closes"
    raise ValueError(f"a pair file name starts with fit- or close-: {name}")


def pair_group(p: dict) -> str:
    """The pairs with the same text A are one group: the candidates of one text."""
    return p.get("group") or (p["a"].get("kind", "") + "\x1f" + p["a"].get("text", ""))

# Made-up data only (build spec 2, rule 2): each address and each web link uses an example domain.
_EXAMPLE_DOMAIN = re.compile(r"(^|\.)example\.(com|org|net)$")
_ADDRESS = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
_LINK = re.compile(r"https?://([A-Za-z0-9.-]+)")


def _open(path: Path, mode: str):
    path = Path(path)
    if path.suffix == ".gz":
        return gzip.open(path, mode + "t", encoding="utf-8")
    return open(path, mode, encoding="utf-8")


def read_jsonl(path: Path) -> list[dict]:
    rows = []
    with _open(path, "r") as f:
        for n, line in enumerate(f, 1):
            if line.strip():
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError as e:
                    raise ValueError(f"{path}: line {n} is not JSON: {e}") from e
    return rows


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == ".gz":
        # No name and mtime 0 make the file the same for the same rows, so that a SHA-256 value does not change.
        with open(path, "wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as g:
            for r in rows:
                g.write((json.dumps(r, ensure_ascii=False) + "\n").encode("utf-8"))
    else:
        with open(path, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")


def read_tsv(path: Path) -> list[dict]:
    with _open(path, "r") as f:
        lines = [l.rstrip("\n").rstrip("\r") for l in f if l.strip()]
    if not lines:
        return []
    head = lines[0].split("\t")
    out = []
    for l in lines[1:]:
        cells = l.split("\t")
        cells += [""] * (len(head) - len(cells))
        out.append(dict(zip(head, cells)))
    return out


def write_tsv(path: Path, columns: tuple[str, ...], rows: list[dict]) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(columns) + "\n")
        for r in rows:
            f.write("\t".join(clean_cell(str(r.get(c, ""))) for c in columns) + "\n")


def clean_cell(s: str) -> str:
    """A TSV cell has no tab and no line end. The Swift bench cleans its sentence in the same way."""
    return s.replace("\t", " ").replace("\r", " ").replace("\n", " ")


def is_note(item: dict) -> bool:
    """RULE-need.md: a note has an empty `from_address`."""
    return item.get("kind") == "note" or not item.get("from_address")


def code_gate(item: dict) -> bool:
    """Build spec 3 (design thread, 2026-11-16): facts gate the item before the model, like the bulk filter.
    If the owner replied, or the owner sent the mail, the result is `none` and the model does not run."""
    if item.get("replied"):
        return True
    sender = item.get("from_address", "").lower()
    return bool(sender) and sender == item.get("owner", {}).get("address", "").lower()


def same_sentence(a: str, b: str) -> bool:
    norm = lambda s: " ".join(clean_cell(s).split())
    return bool(a.strip()) and norm(a) == norm(b)


def label_file(data_file: Path) -> Path:
    """`x.jsonl.gz` and `x.jsonl` have the labels in `x-labels.tsv`."""
    p = Path(data_file)
    name = p.name
    for suf in (".jsonl.gz", ".jsonl"):
        if name.endswith(suf):
            return p.with_name(name[: -len(suf)] + "-labels.tsv")
    raise ValueError(f"not a data file: {p}")


def made_up_problems(text: str) -> list[str]:
    """Addresses and links that do not use an example domain."""
    bad = []
    for m in _ADDRESS.finditer(text):
        if not _EXAMPLE_DOMAIN.search(m.group(1).lower()):
            bad.append(m.group(0))
    for m in _LINK.finditer(text):
        if not _EXAMPLE_DOMAIN.search(m.group(1).lower().rstrip(".")):
            bad.append(m.group(0))
    return bad


def check_items(items: list[dict], labels: list[dict] | None) -> list[str]:
    """The problems of an item file and its labels. An empty list means that the files are correct."""
    problems = []
    ids = set()
    for it in items:
        i = it.get("id", "?")
        missing = [f for f in ITEM_FIELDS if f not in it]
        if missing:
            problems.append(f"{i}: missing {', '.join(missing)}")
            continue
        if i in ids:
            problems.append(f"{i}: id is not unique")
        ids.add(i)
        own = it["owner"]
        if not isinstance(own, dict) or not own.get("name") or not own.get("address"):
            problems.append(f"{i}: owner needs name and address")
        elif not _EXAMPLE_DOMAIN.search(own["address"].split("@")[-1].lower()):
            problems.append(f"{i}: owner address is not an example address")
        text = " ".join([it["from_address"], *it["to"], *it["cc"], it["body"], it["subject"]])
        for b in made_up_problems(text):
            problems.append(f"{i}: not an example domain: {b}")
    if labels is not None:
        by_id = {it.get("id"): it for it in items}
        seen = set()
        for r in labels:
            i = r.get("id", "")
            seen.add(i)
            if i not in by_id:
                problems.append(f"{i}: label with no item")
                continue
            if r.get("need") not in NEED_VALUES:
                problems.append(f"{i}: need must be none, list or now")
            if r.get("need") == "now" and is_note(by_id[i]):
                problems.append(f"{i}: a note is never now")
            body = " ".join(by_id[i]["body"].split())
            for col in ("sentence", "sentence2"):
                s = r.get(col, "")
                if s and " ".join(s.split()) not in body:
                    problems.append(f"{i}: {col} is not in the body")
            if is_request(r) and not r.get("sentence"):
                problems.append(f"{i}: a request needs a sentence")
        for i in ids - seen:
            problems.append(f"{i}: item with no label")
    return problems


def check_pairs(pairs: list[dict], labels: list[dict] | None) -> list[str]:
    problems = []
    ids = set()
    for p in pairs:
        i = p.get("id", "?")
        for f in ("id", "owner", "a", "b"):
            if f not in p:
                problems.append(f"{i}: missing {f}")
        if any(f not in p for f in ("a", "b")):
            continue
        if i in ids:
            problems.append(f"{i}: id is not unique")
        ids.add(i)
        a, b = p["a"], p["b"]
        if not isinstance(a, dict) or not a.get("text") or not a.get("kind"):
            problems.append(f"{i}: a needs text and kind")
        if not isinstance(b, dict) or not b.get("name") or b.get("kind") not in ("project", "item"):
            problems.append(f"{i}: b needs a name and the kind project or item")
        elif len(b.get("records", [])) > 5:
            problems.append(f"{i}: b has more than 5 records")
        text = json.dumps(p, ensure_ascii=False)
        for bad in made_up_problems(text):
            problems.append(f"{i}: not an example domain: {bad}")
    if labels is not None:
        seen = set()
        for r in labels:
            i = r.get("id", "")
            seen.add(i)
            if i not in ids:
                problems.append(f"{i}: label with no pair")
            if r.get("label") not in ("0", "1"):
                problems.append(f"{i}: label must be 0 or 1")
        for i in ids - seen:
            problems.append(f"{i}: pair with no label")
    return problems
