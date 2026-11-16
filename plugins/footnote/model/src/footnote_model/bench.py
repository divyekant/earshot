"""The bench of E13. It reads made-up data and prints counts only.

Arms:
- `rules`: the rules of today, from the Swift program (`footnote --decide-bench`). D1 and D4 only.
- `pred:<file>`: a predictions file of another arm, in the same format.

A sealed set runs one time (build spec 2, rule 5). `sealed_run` checks the SHA-256 values first, refuses a second
run, prints counts only, and records the run in `runs/`.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import os
import subprocess
import tempfile
from pathlib import Path

from . import marks
from .formats import read_jsonl, read_tsv, write_jsonl

MODEL_DIR = Path(__file__).resolve().parents[2]
PLUGIN_DIR = MODEL_DIR.parent
RUNS_DIR = MODEL_DIR / "runs"


def footnote_binary() -> Path:
    env = os.environ.get("FOOTNOTE_BIN")
    if env:
        return Path(env)
    for c in ("release", "debug"):
        p = PLUGIN_DIR / ".build" / c / "footnote"
        if p.exists():
            return p
    raise FileNotFoundError("No footnote program. Run `swift build` in plugins/footnote, or set FOOTNOTE_BIN.")


def rules_predictions(items: list[dict]) -> dict[str, dict]:
    """Runs the rules arm on the items. The temporary files are removed before the return."""
    with tempfile.TemporaryDirectory() as d:
        src, out = Path(d) / "items.jsonl", Path(d) / "pred.tsv"
        write_jsonl(src, items)
        r = subprocess.run([str(footnote_binary()), "--decide-bench", str(src), "--out", str(out)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("rules arm failed: " + r.stdout.strip()[-300:])
        return {row["id"]: row for row in read_tsv(out)}


def arm_predictions(arm: str, items: list[dict]) -> dict[str, dict]:
    if arm == "rules":
        return rules_predictions(items)
    if arm.startswith("pred:"):
        return {row["id"]: row for row in read_tsv(Path(arm[5:]))}
    raise ValueError(f"unknown arm: {arm}")


def score_items(items: list[dict], labels: list[dict], preds: dict[str, dict]) -> list[marks.Result]:
    out = []
    if any(it["kind"] == "mail" for it in items):
        out.append(marks.d1_mail(items, labels, preds))
    if any(it["kind"] == "note" for it in items):
        out.append(marks.d1_notes(items, labels, preds))
    if any(r.get("when") for r in labels):
        out.append(marks.d4(items, labels, preds))
    return out


def table(rows: list[tuple[str, list[marks.Result]]]) -> str:
    lines = ["| Set | Arm | Decision | Counts | Mark |", "|---|---|---|---|---|"]
    for label, results in rows:
        set_name, arm = label.split(" / ", 1)
        for r in results:
            c = ", ".join(f"{k} {v}" for k, v in r.counts.items())
            p = "n/a" if r.passed is None else ("PASS" if r.passed else "FAIL")
            lines.append(f"| {set_name} | {arm} | {r.decision} | {c} | {p} |")
    return "\n".join(lines)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_sha(sha_file: Path, files: list[Path]) -> list[str]:
    """The `.sha256` file has lines `<hash>  <file name>`, as `sha256sum` writes them."""
    want = {}
    for line in Path(sha_file).read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2:
            want[Path(parts[-1].lstrip("*")).name] = parts[0].lower()
    problems = []
    for f in files:
        w = want.get(f.name)
        if w is None:
            problems.append(f"{f.name}: no SHA-256 value")
        elif sha256(f) != w:
            problems.append(f"{f.name}: SHA-256 value is not equal")
    return problems


def sealed_run(set_name: str, data_file: Path, sha_file: Path, arms: list[str], runs_dir: Path = RUNS_DIR,
               predict=arm_predictions) -> str:
    """One run on a sealed item set. It prints counts only and records the run."""
    from .formats import label_file
    record = runs_dir / f"{set_name}.md"
    if record.exists():
        raise RuntimeError(f"{set_name} has a run already ({record}). A sealed set runs one time.")
    labels_path = label_file(data_file)
    bad = check_sha(sha_file, [data_file, labels_path])
    if bad:
        raise RuntimeError("SHA-256 check failed: " + "; ".join(bad))
    items, labels = read_jsonl(data_file), read_tsv(labels_path)
    rows = [(f"{set_name} / {a}", score_items(items, labels, predict(a, items))) for a in arms]
    text = table(rows)
    runs_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    record.write_text(f"# Sealed run: {set_name}\n\n{stamp}. SHA-256 checked. Arms: {', '.join(arms)}.\n\n{text}\n")
    return text
