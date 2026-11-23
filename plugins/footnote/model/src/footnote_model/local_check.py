"""E13 package L1: the check of the rules and the model on the owner's recent mail, on the owner's Mac.

Spec: `/mnt/project-files/earshot-footnote-model/local-check-spec.md`. The configuration is in `l1-config.json`.

Hard rules (spec section 2):
- The mail text stays on the Mac. The files of this check stay in one folder (`--dir`).
- No command prints a field of a mail. The commands print counts, and the address of the list page on the loopback
  address. A test runs every command on made-up mail and checks the output.
- No network: the models load from local folders (`hf` beside the weights), and the list page listens on 127.0.0.1.
- No fit.

Steps: `fm local-check score|counts|list|marks|clean --dir <folder>`. `footnote --decide-export` writes
`<folder>/export.jsonl` before `score`.
"""

from __future__ import annotations

import html
import json
import os
import random
import resource
import subprocess
import sys
import time
from pathlib import Path

from .formats import code_gate, read_jsonl, read_tsv, write_jsonl

CONFIG = Path(__file__).resolve().parents[2] / "l1-config.json"

EXPORT, SCORES, COST = "export.jsonl", "scores.tsv", "cost.json"
LIST, GROUPS, MARKS, SUMMARY = "list.html", "list-groups.json", "marks.json", "marks-summary.tsv"
RULES_IN, RULES_OUT = "rules-items.jsonl", "rules-pred.tsv"
GATE2 = ("greets another", "not for owner")
GROUPS_ORDER = ("both", "model only", "rules only", "none")


def load_config(path: Path = CONFIG) -> dict:
    return json.loads(Path(path).read_text())


def _private(path: Path) -> None:
    if path.exists():
        os.chmod(path, 0o600)


# --- score ---------------------------------------------------------------------------------------------------


def rules_in_folder(d: Path, items: list[dict]) -> dict[str, dict]:
    """The rules arm (`footnote --decide-bench`), with its files in the folder of the check, not in /tmp."""
    from .bench import footnote_binary
    src, out = d / RULES_IN, d / RULES_OUT
    try:
        write_jsonl(src, items)
        _private(src)
        r = subprocess.run([str(footnote_binary()), "--decide-bench", str(src), "--out", str(out)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            # The output of the bench is counts only, but keep only the exit code here.
            raise RuntimeError(f"rules arm failed with exit code {r.returncode}")
        _private(out)
        return {row["id"]: row for row in read_tsv(out)}
    finally:
        for p in (src, out):
            if p.exists():
                p.unlink()


def sender_known(items: list[dict]) -> dict[str, bool]:
    """As `DecideBench`: a sender is known if an earlier mail of this sender passed the bulk filter. The export
    cannot see whether the owner wrote to the address before."""
    first: dict[str, str] = {}
    for it in items:
        if code_gate(it) is None:
            k = it["owner"]["address"] + " " + it.get("from_address", "").lower()
            if k not in first or it["date"] < first[k]:
                first[k] = it["date"]
    out = {}
    for it in items:
        k = it["owner"]["address"] + " " + it.get("from_address", "").lower()
        out[it["id"]] = k in first and first[k] < it["date"]
    return out


def score(d: Path, cfg: dict, rules=rules_in_folder, models=None) -> None:
    """Runs the three arms and writes `scores.tsv`. Prints nothing."""
    items = read_jsonl(d / EXPORT)
    t0 = time.perf_counter()
    sw = rules(d, items)
    t_rules = time.perf_counter() - t0
    if models is None:
        import hashlib
        models = []
        for m in cfg["models"]:
            f = Path(cfg["model_root"]).expanduser() / m["folder"]
            if hashlib.sha256((f / "model.pt").read_bytes()).hexdigest() != m["sha256"]:
                raise RuntimeError(f"the model file {m['folder']} is not the declared file")
            models.append(f)
    per_model, t_model = [], 0.0
    for m in models:
        if callable(m):
            res = m(items, sw)
        else:
            os.environ.setdefault("HF_HUB_OFFLINE", "1")
            os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
            from . import fit
            model, tok, _ = fit.load(Path(m))
            t1 = time.perf_counter()
            # Mails that the bulk filter holds reach no arm, so the model does not read them.
            passing = [it for it in items if code_gate(it) is None]
            res = fit.predict_items(model, tok, fit.item_examples(tok, passing, None, sw))
            t_model += time.perf_counter() - t1
        per_model.append(res)
    known = sender_known(items)
    rows = ["id\tbulk\tgate2\trules\tp_req\tp_now\tknown\t" + "\t".join(f"p_req_{i}" for i in range(len(per_model)))]
    reaching = 0
    for it in items:
        i = it["id"]
        bulk = code_gate(it) or ""
        reaching += not bulk
        reqs = [r.get(i, {}).get("p_req", 0.0) for r in per_model]
        nows = [r.get(i, {}).get("p_now", 0.0) for r in per_model]
        s = sw.get(i, {})
        rows.append("\t".join([i, bulk, "yes" if s.get("gate", "") in GATE2 else "no",
                               "1" if s.get("need") == "1" and not bulk else "0",
                               f"{sum(reqs) / len(reqs):.4f}", f"{sum(nows) / len(nows):.4f}",
                               "yes" if known[i] else "no"] + [f"{v:.4f}" for v in reqs]))
    (d / SCORES).write_text("\n".join(rows) + "\n")
    _private(d / SCORES)
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # macOS gives bytes, Linux kilobytes.
    peak_mb = peak / 1e6 if sys.platform == "darwin" else peak / 1e3
    cost = {"mails": len(items), "mails_reaching_arms": reaching, "rules_seconds": round(t_rules, 2),
            "model_seconds_3_models": round(t_model, 2),
            "model_ms_per_mail_3_models": round(1000 * t_model / max(1, reaching), 1),
            "peak_memory_mb": round(peak_mb, 1)}
    (d / COST).write_text(json.dumps(cost))


# --- counts --------------------------------------------------------------------------------------------------


def read_scores(d: Path) -> list[dict]:
    return read_tsv(d / SCORES)


def flags(rows: list[dict], cfg: dict, t: float) -> dict[str, set[str]]:
    reach = [r for r in rows if not r["bulk"]]
    model = {r["id"] for r in reach if float(r["p_req"]) >= t}
    g2 = {r["id"] for r in reach if float(r["p_req"]) >= t and r["gate2"] == "no"}
    rules = {r["id"] for r in reach if r["rules"] == "1"}
    return {"rules": rules, "model": model, "model+g2": g2}


def groups(rows: list[dict], cfg: dict) -> dict[str, list[str]]:
    """The four groups of the list at the primary threshold: rules against model+g2."""
    f = flags(rows, cfg, cfg["primary_threshold"])
    reach = [r["id"] for r in rows if not r["bulk"]]
    m, r = f["model+g2"], f["rules"]
    return {"both": [i for i in reach if i in m and i in r], "model only": [i for i in reach if i in m and i not in r],
            "rules only": [i for i in reach if i in r and i not in m],
            "none": [i for i in reach if i not in m and i not in r]}


def counts_text(d: Path, cfg: dict) -> str:
    rows = read_scores(d)
    from collections import Counter
    held = Counter(r["bulk"] for r in rows if r["bulk"])
    reach = [r for r in rows if not r["bulk"]]
    out = [f"Mails read: {len(rows)} in {cfg['days']} days. Held by the bulk filter: {sum(held.values())}. "
           f"Reach the arms: {len(reach)}."]
    out.append("Held by reason: " + ", ".join(f"{k} {v}" for k, v in sorted(held.items(), key=lambda x: -x[1])))
    out.append("Requests that the filter holds cannot be seen in this check.")
    rules_n = sum(1 for r in reach if r["rules"] == "1")
    out.append(f"Flags, rules: {rules_n}")
    for t in cfg["thresholds"]:
        f = flags(rows, cfg, t)
        out.append(f"Flags at {t}: model {len(f['model'])}, model+g2 {len(f['model+g2'])}")
    g = groups(rows, cfg)
    out.append(f"Overlap at {cfg['primary_threshold']} (rules against model+g2): " +
               ", ".join(f"{k} {len(v)}" for k, v in g.items()))
    tn = cfg["now_threshold"]
    for t in cfg["thresholds"]:
        f = flags(rows, cfg, t)
        by = {r["id"]: r for r in reach}
        for arm in ("model", "model+g2"):
            now = [i for i in f[arm] if float(by[i]["p_now"]) >= tn]
            after = [i for i in now if by[i]["known"] == "yes"]
            out.append(f"now at {t}, {arm}: {len(now)} before the sender gate, {len(after)} after it "
                       "(known = an earlier mail of the sender passed the filter)")
    out.append("now, rules: 0 (the rules of today give no now)")
    if (d / COST).exists():
        out.append("Cost: " + ", ".join(f"{k} {v}" for k, v in json.loads((d / COST).read_text()).items()))
    return "\n".join(out)


# --- list ----------------------------------------------------------------------------------------------------


def sample(rows: list[dict], cfg: dict) -> list[tuple[str, str]]:
    """(id, group) for each line of the list, in random order, with the declared seed."""
    rng = random.Random(cfg["sample"]["seed"])
    g = groups(rows, cfg)
    picked = []
    for name in GROUPS_ORDER:
        ids = sorted(g[name])
        n = cfg["sample"]["per_group"][name]
        picked += [(i, name) for i in (rng.sample(ids, n) if len(ids) > n else ids)]
    rng.shuffle(picked)
    return picked


PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mail check</title><style>
:root{--bg:#fbfbf9;--ink:#1c1c1a;--ink2:#5c5c57;--line:#e4e4df;--on:#1c1c1a;--onink:#fbfbf9}
@media (prefers-color-scheme:dark){:root{--bg:#0c0c0b;--ink:#f2f2ee;--ink2:#a8a8a2;--line:#2a2a27;--on:#f2f2ee;--onink:#0c0c0b}}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 -apple-system,system-ui,sans-serif}
main{max-width:720px;margin:0 auto;padding:32px 16px 96px}
h1{font-size:22px;margin:0 0 4px}p.lead{color:var(--ink2);margin:0 0 24px}
.m{border-top:1px solid var(--line);padding:20px 0}.who{color:var(--ink2);font-size:14px}
.sub{font-weight:600;margin:2px 0 8px}.body{white-space:pre-wrap;color:var(--ink2);font-size:15px}
details summary{cursor:pointer;color:var(--ink2);font-size:14px;margin-top:6px}
.b{display:flex;gap:12px;margin-top:14px}.b button{flex:1;padding:14px;font-size:16px;border-radius:10px;
border:1px solid var(--line);background:transparent;color:var(--ink);cursor:pointer}
.b button.on{background:var(--on);color:var(--onink);border-color:var(--on)}
#done{width:100%;padding:16px;font-size:17px;border-radius:10px;border:0;background:var(--on);color:var(--onink);margin-top:24px}
</style></head><body><main><h1>Mail check</h1>
<p class="lead">For each mail: did it need an answer or an act from you? Your marks save at once. You can leave a mail not marked.</p>
%LINES%
<button id="done">Done</button><p class="lead" id="end"></p></main>
<script>
function send(path,body){return fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)})}
document.querySelectorAll('.b button').forEach(function(b){b.addEventListener('click',function(){
var line=b.parentNode.dataset.line;b.parentNode.querySelectorAll('button').forEach(function(x){x.classList.remove('on')});
b.classList.add('on');send('/mark',{line:Number(line),mark:b.dataset.mark})})});
document.getElementById('done').addEventListener('click',function(){send('/done',{}).then(function(){
document.getElementById('end').textContent='Thank you. You can close this page.'})});
</script></body></html>"""


def page(items: dict[str, dict], picked: list[tuple[str, str]]) -> str:
    lines = []
    for n, (i, _) in enumerate(picked, 1):
        it = items[i]
        body = it.get("body", "")
        who = (f"{html.escape(it.get('from_name', ''))} &lt;{html.escape(it.get('from_address', ''))}&gt; · "
               f"{html.escape(it.get('date', '')[:10])}")
        more = f"<details><summary>Show the full mail</summary><div class='body'>{html.escape(body)}</div></details>" \
            if len(body) > 300 else ""
        lines.append(f"<section class='m'><div class='who'>{who}</div>"
                     f"<div class='sub'>{html.escape(it.get('subject', ''))}</div>"
                     f"<div class='body'>{html.escape(body[:300])}</div>{more}"
                     f"<div class='b' data-line='{n}'><button data-mark='needed'>Needed me</button>"
                     f"<button data-mark='not needed'>Did not need me</button></div></section>")
    return PAGE.replace("%LINES%", "\n".join(lines))


def make_list(d: Path, cfg: dict) -> int:
    if (d / GROUPS).exists() or (d / SUMMARY).exists():
        raise RuntimeError("a list was made already (spec 2.8: one list)")
    rows = read_scores(d)
    items = {it["id"]: it for it in read_jsonl(d / EXPORT)}
    picked = sample(rows, cfg)
    (d / GROUPS).write_text(json.dumps({str(n): {"id": i, "group": g} for n, (i, g) in enumerate(picked, 1)}))
    (d / LIST).write_text(page(items, picked))
    for p in (d / GROUPS, d / LIST):
        _private(p)
    return len(picked)


def serve(d: Path, open_browser: bool = True) -> None:
    """Serves the list on the loopback address until the owner presses Done. Each mark saves at once."""
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import threading

    marks_path = d / MARKS
    marks = json.loads(marks_path.read_text()) if marks_path.exists() else {}
    n_lines = len(json.loads((d / GROUPS).read_text()))

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):  # no access log: it holds nothing of a mail, but stay quiet
            pass

        def do_GET(self):
            if self.path != "/":
                self.send_error(404)
                return
            data = (d / LIST).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            n = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(n) or b"{}")
            if self.path == "/mark" and body.get("mark") in ("needed", "not needed") \
                    and isinstance(body.get("line"), int) and 1 <= body["line"] <= n_lines:
                marks[str(body["line"])] = body["mark"]
                marks_path.write_text(json.dumps(marks))
                _private(marks_path)
            elif self.path == "/done":
                threading.Thread(target=srv.shutdown).start()
            else:
                self.send_error(400)
                return
            self.send_response(204)
            self.end_headers()

    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    url = f"http://127.0.0.1:{srv.server_address[1]}/"
    print(f"List: {n_lines} lines at {url}", flush=True)
    if open_browser:
        subprocess.run(["open", url] if sys.platform == "darwin" else ["xdg-open", url], check=False)
    srv.serve_forever()
    print(f"List closed: {len(marks)} of {n_lines} lines marked", flush=True)


# --- marks and clean -----------------------------------------------------------------------------------------


def marks_text(d: Path) -> str:
    if (d / SUMMARY).exists():
        rows = read_tsv(d / SUMMARY)
    else:
        g = json.loads((d / GROUPS).read_text())
        m = json.loads((d / MARKS).read_text()) if (d / MARKS).exists() else {}
        rows = [{"line": n, "group": v["group"], "mark": m.get(n, "")} for n, v in g.items()]
    out = []
    for name in GROUPS_ORDER:
        sub = [r for r in rows if r["group"] == name]
        need = sum(r["mark"] == "needed" for r in sub)
        no = sum(r["mark"] == "not needed" for r in sub)
        out.append(f"{name}: {len(sub)} lines, needed me {need}, did not need me {no}, not marked {len(sub) - need - no}")
    return "\n".join(out)


def clean(d: Path) -> list[str]:
    """Keeps a marks file with no text (line, group, mark), then deletes the files of the check by their paths."""
    if (d / GROUPS).exists():
        g = json.loads((d / GROUPS).read_text())
        m = json.loads((d / MARKS).read_text()) if (d / MARKS).exists() else {}
        (d / SUMMARY).write_text("line\tgroup\tmark\n" + "".join(f"{n}\t{v['group']}\t{m.get(n, '')}\n" for n, v in g.items()))
    gone = []
    for name in (EXPORT, SCORES, COST, LIST, GROUPS, MARKS, RULES_IN, RULES_OUT):
        p = d / name
        if p.exists():
            p.unlink()
            gone.append(name)
    return gone


def main(step: str, d: Path, cfg_path: Path = CONFIG, open_browser: bool = True) -> int:
    cfg = load_config(cfg_path)
    if step == "score":
        score(d, cfg)
    elif step == "counts":
        print(counts_text(d, cfg))
    elif step == "list":
        n = make_list(d, cfg)
        print(f"List made: {n} lines")
        serve(d, open_browser)
    elif step == "marks":
        print(marks_text(d))
    elif step == "clean":
        print("Deleted: " + ", ".join(clean(d)))
    else:
        raise ValueError(step)
    return 0
