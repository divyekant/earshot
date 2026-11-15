# Writes build-a.jsonl and build-a-labels.tsv (flags v2 data) from part1.py to part5.py.
# Usage: python3 -I dump.py <out folder>. All data is made up.
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import part1, part2, part3, part4, part5  # noqa: E401,F401  each part appends to part1.R
R = part1.R
out = sys.argv[1]
ids = [r["id"] for r in R]
assert len(ids) == len(set(ids)) == 300, len(ids)
assert sum(r["request"] for r in R) == 45
for r in R:
    for s in (r["sentence"], r["sentence2"]):
        assert s == "" or s in r["body"], (r["id"], s)
    assert (r["request"] == 1) == (r["sentence"] != ""), r["id"]
keys = ["id", "from_name", "from_address", "to", "cc", "subject", "date", "list_unsubscribe", "precedence",
        "auto_submitted", "junk", "replied", "body"]
with open(os.path.join(out, "build-a.jsonl"), "w") as f:
    for r in R:
        f.write(json.dumps({k: r[k] for k in keys}, ensure_ascii=False) + "\n")
with open(os.path.join(out, "build-a-labels.tsv"), "w") as f:
    f.write("id\trequest\tkind\tsentence\tsentence2\n")
    for r in R:
        f.write("\t".join([r["id"], str(r["request"]), r["kind"], r["sentence"], r["sentence2"]]) + "\n")
print("messages", len(R), "requests", sum(r["request"] for r in R))
