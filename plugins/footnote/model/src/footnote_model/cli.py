"""`uv run fm <command>`. See README.md."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import bench
from .formats import check_items, check_pairs, label_file, read_jsonl, read_tsv
from .importers import PHASE3_SETS, phase3_set

PHASE3 = bench.PLUGIN_DIR / "Tests/FootnoteCoreTests/Fixtures/phase3/mail"


def cmd_check(a) -> int:
    bad_total = 0
    for f in a.files:
        f = Path(f)
        rows = read_jsonl(f)
        lp = label_file(f)
        labels = read_tsv(lp) if lp.exists() else None
        problems = check_pairs(rows, labels) if rows and "task" in rows[0] else check_items(rows, labels)
        for p in problems[:50]:
            print(f"{f.name}: {p}")
        print(f"{f.name}: {len(rows)} rows, {len(problems)} problems" + ("" if labels is not None else ", no label file"))
        bad_total += len(problems)
    return 1 if bad_total else 0


def cmd_rules_seen(a) -> int:
    """The rules arm on the seen phase 3 sets (package M0)."""
    rows = []
    for name in PHASE3_SETS:
        items, labels = phase3_set(PHASE3, name)
        rows.append((f"{name} / rules", bench.score_items(items, labels, bench.rules_predictions(items))))
    print(bench.table(rows))
    return 0


def cmd_bench(a) -> int:
    rows = []
    for f in a.files:
        f = Path(f)
        items, labels = read_jsonl(f), read_tsv(label_file(f))
        for arm in a.arm:
            rows.append((f"{f.name} / {arm}", bench.score_items(items, labels, bench.arm_predictions(arm, items))))
    print(bench.table(rows))
    return 0


def cmd_sealed(a) -> int:
    try:
        print(bench.sealed_run(a.name, Path(a.file), Path(a.sha256), a.arm))
    except RuntimeError as e:
        print(f"Refused: {e}")
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="fm", description="The decision model of Footnote (E13).")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="Check data files and their labels.")
    c.add_argument("files", nargs="+")
    c.set_defaults(fn=cmd_check)
    r = sub.add_parser("rules-seen", help="The rules arm on the seen phase 3 sets.")
    r.set_defaults(fn=cmd_rules_seen)
    b = sub.add_parser("bench", help="Marks of arms on item files that are not sealed.")
    b.add_argument("files", nargs="+")
    b.add_argument("--arm", action="append", default=None)
    b.set_defaults(fn=cmd_bench)
    s = sub.add_parser("sealed", help="The one run on a sealed item set. Counts only.")
    s.add_argument("name")
    s.add_argument("file")
    s.add_argument("--sha256", required=True)
    s.add_argument("--arm", action="append", default=None)
    s.set_defaults(fn=cmd_sealed)
    a = ap.parse_args(argv)
    if getattr(a, "arm", "x") is None:
        a.arm = ["rules"]
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
