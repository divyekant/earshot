"""Assemble the M1 fit data: labeler labels, kept only where the writer intent agrees. Dev = 1 owner per mail
writer, 2 owners per pair writer (the last owner(s) by name order)."""
import glob, json, re, sys, collections
sys.path.insert(0, "/home/user/earshot/plugins/footnote/model/src")
from footnote_model.formats import write_jsonl, write_tsv, NEED_LABEL_COLUMNS, PAIR_LABEL_COLUMNS, made_up_problems
OUT = "/home/user/earshot/plugins/footnote/model/data"
BANNED = ["Nadia Brandt", "Walter Osei", "Tomasz Wilk", "Ingrid Halvorsen", "Dev Malhotra", "Ruth Abernathy", "Kenji Morales"]
def rows(pat):
    out = {}
    for f in sorted(glob.glob(pat)):
        L = open(f).read().splitlines(); h = L[0].split("\t")
        for l in L[1:]:
            if l.strip():
                c = l.split("\t"); c += [""] * (len(h) - len(c)); out[c[0]] = dict(zip(h, c))
    return out
def fix_domains(s):
    for bad in made_up_problems(s):
        if "@" in bad:
            user, dom = bad.split("@", 1)
            s = s.replace(bad, f"{user}@{dom.split('.')[0]}.example.org")
        else:
            host = re.match(r"https?://([^/]+)", bad).group(1)
            s = s.replace(bad, bad.replace(host, host.split(".")[0] + ".example.net", 1))
    return s
def clean(obj):
    return json.loads(fix_domains(json.dumps(obj, ensure_ascii=False)))
stats = collections.Counter()
def items(writers, dev_owner_count=1):
    fit, dev = ([], []), ([], [])
    for w in writers:
        its = [json.loads(l) for f in sorted(glob.glob(f"/home/user/e13-raw/{w}/items-*.jsonl")) for l in open(f) if l.strip()]
        lab = rows(f"/home/user/e13-raw/lab/{w}/*-labels.tsv"); intent = rows(f"/home/user/e13-tools/intent/{w}/intent-*.tsv")
        owners = sorted({it["owner"]["name"] for it in its}); devo = set(owners[-dev_owner_count:]) if dev_owner_count else set()
        for it in its:
            i = it["id"]
            if any(b in json.dumps(it) for b in BANNED): stats["banned"] += 1; continue
            if i not in lab or i not in intent: stats["no label"] += 1; continue
            if lab[i]["need"] != intent[i]["need"]: stats["disagree"] += 1; continue
            l = dict(lab[i])
            if not l.get("sentence2") and intent[i].get("sentence") and intent[i]["sentence"] != l.get("sentence"):
                l["sentence2"] = intent[i]["sentence"]
            tgt = dev if it["owner"]["name"] in devo else fit
            tgt[0].append(clean(it)); tgt[1].append(l); stats["kept"] += 1
    return fit, dev
def pairs(writers, task, dev_owner_count=2):
    fit, dev = ([], []), ([], [])
    for w in writers:
        ps = [json.loads(l) for f in sorted(glob.glob(f"/home/user/e13-raw/{w}/{task}-*.jsonl")) for l in open(f) if l.strip()]
        lab = rows(f"/home/user/e13-raw/lab/{w}/*-labels.tsv"); intent = rows(f"/home/user/e13-tools/intent/{w}/*-intent.tsv")
        owners = sorted({p["owner"]["name"] for p in ps}); devo = set(owners[-dev_owner_count:]) if dev_owner_count else set()
        for p in ps:
            i = p["id"]
            if any(b in json.dumps(p) for b in BANNED): stats["banned"] += 1; continue
            if i not in lab or i not in intent: stats["no label"] += 1; continue
            if lab[i]["label"] != intent[i]["label"]: stats["disagree"] += 1; continue
            tgt = dev if p["owner"]["name"] in devo else fit
            tgt[0].append(clean(p)); tgt[1].append(lab[i]); stats["kept"] += 1
    return fit, dev
if __name__ == "__main__":
    what = sys.argv[1]
    sfx = sys.argv[3] if len(sys.argv) > 3 else ""  # round 2: "2" writes items-fit2, items-dev2, ...
    if what == "items":
        f, d = items(sys.argv[2].split(","), 0 if sfx == "3" else 1)  # round 3 is fit only
        for name, (a, b) in ((f"items-fit{sfx}", f), (f"items-dev{sfx}", d)):
            if a: write_jsonl(f"{OUT}/{name}.jsonl.gz", a); write_tsv(f"{OUT}/{name}-labels.tsv", NEED_LABEL_COLUMNS, b)
    else:
        task = what  # fit or close
        f, d = pairs(sys.argv[2].split(","), task, 0 if sfx == "3" else 2)
        for name, (a, b) in ((f"{task}-train{sfx}", f), (f"{task}-dev{sfx}", d)):
            if a: write_jsonl(f"{OUT}/{name}.jsonl.gz", a); write_tsv(f"{OUT}/{name}-labels.tsv", PAIR_LABEL_COLUMNS, b)
    print(dict(stats))
