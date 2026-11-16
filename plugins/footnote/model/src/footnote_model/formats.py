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

ITEM_FIELDS = ("id", "kind", "owner", "now", "from_name", "from_address", "to", "cc", "subject", "date",
               "list_unsubscribe", "precedence", "auto_submitted", "junk", "replied", "body")
NEED_LABEL_COLUMNS = ("id", "need", "when", "category", "sentence", "sentence2")
PAIR_LABEL_COLUMNS = ("id", "label", "category")
WHEN_VALUES = ("none", "list", "now")
PAIR_TASKS = ("fit", "closes")

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
        if it["kind"] not in ("mail", "note"):
            problems.append(f"{i}: kind must be mail or note")
        own = it["owner"]
        if not isinstance(own, dict) or not own.get("name") or not own.get("address"):
            problems.append(f"{i}: owner needs name and address")
        elif not _EXAMPLE_DOMAIN.search(own["address"].split("@")[-1].lower()):
            problems.append(f"{i}: owner address is not an example address")
        if it["kind"] == "note" and it["from_address"]:
            problems.append(f"{i}: a note has an empty from_address")
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
            if r.get("need") not in ("0", "1"):
                problems.append(f"{i}: need must be 0 or 1")
            if r.get("when", "") not in WHEN_VALUES + ("",):
                problems.append(f"{i}: when must be none, list, now or empty")
            if r.get("need") == "0" and r.get("when") in ("list", "now"):
                problems.append(f"{i}: when is {r['when']} but need is 0")
            body = " ".join(by_id[i]["body"].split())
            for col in ("sentence", "sentence2"):
                s = r.get(col, "")
                if s and " ".join(s.split()) not in body:
                    problems.append(f"{i}: {col} is not in the body")
            if r.get("need") == "1" and by_id[i]["kind"] == "mail" and not r.get("sentence"):
                problems.append(f"{i}: a mail request needs a sentence")
        for i in ids - seen:
            problems.append(f"{i}: item with no label")
    return problems


def check_pairs(pairs: list[dict], labels: list[dict] | None) -> list[str]:
    problems = []
    ids = set()
    for p in pairs:
        i = p.get("id", "?")
        for f in ("id", "task", "group", "a", "b"):
            if f not in p:
                problems.append(f"{i}: missing {f}")
        if any(f not in p for f in ("task", "a", "b")):
            continue
        if i in ids:
            problems.append(f"{i}: id is not unique")
        ids.add(i)
        if p["task"] not in PAIR_TASKS:
            problems.append(f"{i}: task must be fit or closes")
        a, b = p["a"], p["b"]
        if not isinstance(a, dict) or not a.get("text") or not a.get("kind"):
            problems.append(f"{i}: a needs text and kind")
        if not isinstance(b, dict) or not b.get("name") or not b.get("kind"):
            problems.append(f"{i}: b needs kind and name")
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
