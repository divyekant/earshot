"""Stage 1 of E13 (build spec 4.2): heads on a small open encoder, fitted on all four decisions together.

Heads: `need` (3 classes: none, list, now; D1 and D4 in one head), `sentence` (a score at the mark of each
sentence), `fit` (D2) and `closes` (D3). The model gives classes and scores only. It writes no text (R-FN-4).
"""

from __future__ import annotations

import json
import math
import random
import time
from dataclasses import dataclass
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F
from transformers import AutoModel, AutoTokenizer

from .encode import Window, item_windows, pair_ids

NEED = ("none", "list", "now")


class DecisionModel(nn.Module):
    def __init__(self, base: str):
        super().__init__()
        self.encoder = AutoModel.from_pretrained(base)
        h = self.encoder.config.hidden_size
        self.need = nn.Linear(h, 3)
        self.sentence = nn.Linear(h, 1)
        self.fit = nn.Linear(h, 1)
        self.closes = nn.Linear(h, 1)

    def hidden(self, ids, mask):
        return self.encoder(input_ids=ids, attention_mask=mask).last_hidden_state


@dataclass
class ItemEx:
    window: Window
    need: int  # -1: no label for this window
    sentence_targets: list[int]  # 1 for a labeled sentence, per start


@dataclass
class PairEx:
    pid: str
    ids: list[int]
    task: str
    label: int


def _pad(seqs, pad_id):
    n = max(len(s) for s in seqs)
    ids = torch.full((len(seqs), n), pad_id, dtype=torch.long)
    mask = torch.zeros((len(seqs), n), dtype=torch.long)
    for i, s in enumerate(seqs):
        ids[i, : len(s)] = torch.tensor(s)
        mask[i, : len(s)] = 1
    return ids, mask


def norm(s: str) -> str:
    return " ".join(s.replace("\x1e", " ").split())


def item_examples(tok, items, labels, swift) -> list[ItemEx]:
    """`swift` is the rules arm output for the items: the facts line and the prepared sentences."""
    out = []
    lab = {r["id"]: r for r in labels} if labels else {}
    for it in items:
        sw = swift[it["id"]]
        sents = [s for s in sw.get("sentences", "").split("\x1e") if s.strip()]
        ws = item_windows(tok, it["id"], sw["facts"], it.get("subject", ""), sents)
        l = lab.get(it["id"])
        need = NEED.index(l["need"]) if l else -1
        targets = {norm(l.get("sentence", "")), norm(l.get("sentence2", ""))} - {""} if l else set()
        for w in ws:
            st = [1 if norm(s) in targets else 0 for s in w.sentences]
            wn = need
            # A request window that does not hold a labeled sentence teaches nothing sure: no need label.
            if need > 0 and targets and not any(st) and len(ws) > 1:
                wn = -1
            out.append(ItemEx(w, wn, st))
    return out


def pair_examples(tok, pairs, labels, task) -> list[PairEx]:
    lab = {r["id"]: int(r["label"]) for r in labels} if labels else {}
    return [PairEx(p["id"], pair_ids(tok, p["owner"]["name"], p["a"], p["b"]), task, lab.get(p["id"], -1)) for p in pairs]


def batches(exs, size, shuffle, rng):
    idx = list(range(len(exs)))
    if shuffle:
        rng.shuffle(idx)
    # Similar lengths in one batch make the CPU fit faster.
    key = lambda i: len(exs[i].window.ids if isinstance(exs[i], ItemEx) else exs[i].ids)
    chunks = [idx[i : i + size * 20] for i in range(0, len(idx), size * 20)]
    out = []
    for c in chunks:
        c.sort(key=key)
        out += [[exs[i] for i in c[j : j + size]] for j in range(0, len(c), size)]
    if shuffle:
        rng.shuffle(out)
    return out


NEED_WEIGHTS = torch.tensor([1.0, 3.0, 4.0])


def item_loss(model, batch, pad):
    ids, mask = _pad([e.window.ids for e in batch], pad)
    h = model.hidden(ids, mask)
    logits = model.need(h[:, 0])
    y = torch.tensor([e.need for e in batch])
    keep = y >= 0
    loss = F.cross_entropy(logits[keep], y[keep], weight=NEED_WEIGHTS) if keep.any() else logits.sum() * 0
    # Sentence head: only in windows of a request with a labeled sentence.
    rows, cols, tgt = [], [], []
    for i, e in enumerate(batch):
        if e.need > 0 and any(e.sentence_targets):
            for s, t in zip(e.window.starts, e.sentence_targets):
                rows.append(i); cols.append(s); tgt.append(float(t))
    if rows:
        sl = model.sentence(h[rows, cols]).squeeze(-1)
        loss = loss + F.binary_cross_entropy_with_logits(sl, torch.tensor(tgt), pos_weight=torch.tensor(3.0))
    return loss


def pair_loss(model, batch, pad):
    ids, mask = _pad([e.ids for e in batch], pad)
    h = model.hidden(ids, mask)[:, 0]
    loss = 0
    for task, head in (("fit", model.fit), ("closes", model.closes)):
        sel = [i for i, e in enumerate(batch) if e.task == task and e.label >= 0]
        if sel:
            loss = loss + F.binary_cross_entropy_with_logits(head(h[sel]).squeeze(-1),
                                                             torch.tensor([float(batch[i].label) for i in sel]))
    return loss


def train(base: str, item_ex, pair_ex, out_dir: Path, epochs=4, lr=5e-5, batch=16, seed=13, log=print):
    torch.manual_seed(seed)
    rng = random.Random(seed)
    torch.set_num_threads(4)
    tok = AutoTokenizer.from_pretrained(base)
    model = DecisionModel(base)
    pad = tok.pad_token_id
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=0.01)
    steps_total = epochs * (math.ceil(len(item_ex) / batch) + math.ceil(len(pair_ex) / batch))
    sched = torch.optim.lr_scheduler.LambdaLR(opt, lambda s: min(1.0, s / max(1, 0.06 * steps_total)) * max(0.0, 1 - s / steps_total))
    model.train()
    step = 0
    t0 = time.time()
    for ep in range(epochs):
        bs = [("item", b) for b in batches(item_ex, batch, True, rng)] + [("pair", b) for b in batches(pair_ex, batch, True, rng)]
        rng.shuffle(bs)
        total = 0.0
        for kind, b in bs:
            loss = item_loss(model, b, pad) if kind == "item" else pair_loss(model, b, pad)
            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            sched.step()
            step += 1
            total += float(loss.detach())
        log(f"epoch {ep + 1}: mean loss {total / max(1, len(bs)):.4f}, {time.time() - t0:.0f} s")
    out_dir.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), out_dir / "model.pt")
    (out_dir / "config.json").write_text(json.dumps({"base": base, "epochs": epochs, "lr": lr, "batch": batch, "seed": seed}))
    return model, tok


@torch.no_grad()
def predict_items(model, tok, exs: list[ItemEx], batch=32):
    """For each item: p(request) as the highest window value, p(now), and the best sentence."""
    model.eval()
    pad = tok.pad_token_id
    res: dict[str, dict] = {}
    for b in batches(exs, batch, False, None):
        ids, mask = _pad([e.window.ids for e in b], pad)
        h = model.hidden(ids, mask)
        pr = F.softmax(model.need(h[:, 0]), -1)
        for i, e in enumerate(b):
            r = res.setdefault(e.window.item_id, {"p_req": 0.0, "p_now": 0.0, "best": "", "best_s": -1e9})
            r["p_req"] = max(r["p_req"], float(pr[i, 1] + pr[i, 2]))
            r["p_now"] = max(r["p_now"], float(pr[i, 2]))
            if e.window.starts:
                sl = model.sentence(h[i, e.window.starts]).squeeze(-1)
                j = int(sl.argmax())
                if float(sl[j]) > r["best_s"]:
                    r["best_s"], r["best"] = float(sl[j]), e.window.sentences[j]
    return res


@torch.no_grad()
def predict_pairs(model, tok, exs: list[PairEx], batch=64):
    model.eval()
    pad = tok.pad_token_id
    out = {}
    for b in batches(exs, batch, False, None):
        ids, mask = _pad([e.ids for e in b], pad)
        h = model.hidden(ids, mask)[:, 0]
        for i, e in enumerate(b):
            head = model.fit if e.task == "fit" else model.closes
            out[e.pid] = float(torch.sigmoid(head(h[i : i + 1])).squeeze())
    return out


def load(out_dir: Path):
    cfg = json.loads((out_dir / "config.json").read_text())
    tok = AutoTokenizer.from_pretrained(cfg["base"])
    model = DecisionModel(cfg["base"])
    model.load_state_dict(torch.load(out_dir / "model.pt"))
    model.eval()
    return model, tok, cfg
