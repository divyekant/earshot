"""The control arm of E13 (build spec 6): a score on the numbers of the search model (EmbeddingGemma), with no new
model. A logistic fit on the made-up fit data.

The search model runs in `llama-server --embedding` (llama.cpp, MIT) at `EMBED_URL`, with the prefixes of
`LlamaEmbedder.swift`. This is for the bench only. Footnote runs the same model in its worker process.
"""

from __future__ import annotations

import json
import os
import urllib.request

import numpy as np

EMBED_URL = os.environ.get("EMBED_URL", "http://127.0.0.1:8099/v1/embeddings")
QUERY = "task: search result | query: "
PASSAGE = "title: none | text: "


def embed(texts: list[str], prefix: str, batch: int = 32) -> np.ndarray:
    out = []
    for i in range(0, len(texts), batch):
        body = json.dumps({"input": [prefix + t[:2000] for t in texts[i : i + batch]]}).encode()
        req = urllib.request.Request(EMBED_URL, body, {"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r:
            data = json.load(r)["data"]
        out += [d["embedding"] for d in sorted(data, key=lambda d: d["index"])]
    v = np.array(out, dtype=np.float32)
    return v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-9)


class Logistic:
    def __init__(self, lam=0.01, steps=400, lr=0.5):
        self.lam, self.steps, self.lr = lam, steps, lr

    def fit(self, x: np.ndarray, y: np.ndarray, weight_pos: float = 1.0):
        x = np.hstack([x, np.ones((len(x), 1))])
        self.mu = 0
        w = np.zeros(x.shape[1])
        sw = np.where(y > 0, weight_pos, 1.0)
        for _ in range(self.steps):
            p = 1 / (1 + np.exp(-x @ w))
            g = x.T @ ((p - y) * sw) / len(y) + self.lam * np.r_[w[:-1], 0]
            w -= self.lr * g
        self.w = w
        return self

    def p(self, x: np.ndarray) -> np.ndarray:
        x = np.hstack([x, np.ones((len(x), 1))])
        return 1 / (1 + np.exp(-x @ self.w))


def item_text(it: dict, sentences: str) -> str:
    s = [t for t in sentences.split("\x1e") if t.strip()]
    return (it.get("subject", "") + ". " + " ".join(s))[:1500]


def pair_features(pairs: list[dict]) -> np.ndarray:
    """For each pair: cosine of A to the name, the highest and the mean cosine of A to the records."""
    qa = embed([p["a"]["text"] for p in pairs], QUERY)
    names = embed([p["b"]["name"] for p in pairs], PASSAGE)
    feats = []
    recs_all = [r for p in pairs for r in p["b"].get("records", [])]
    rv = embed(recs_all, PASSAGE) if recs_all else np.zeros((0, qa.shape[1]))
    k = 0
    for i, p in enumerate(pairs):
        n = len(p["b"].get("records", []))
        c = rv[k : k + n] @ qa[i] if n else np.array([0.0])
        k += n
        feats.append([float(names[i] @ qa[i]), float(c.max()), float(c.mean()), float(n > 0)])
    return np.array(feats)


def pair_feature_map(pairs: list[dict], cache: "os.PathLike | None" = None) -> dict[str, list[float]]:
    """`pair_features` for each pair id. With `cache`, a JSON file keeps the features of earlier calls."""
    from pathlib import Path

    known: dict[str, list[float]] = {}
    if cache and Path(cache).exists():
        known = json.loads(Path(cache).read_text())
    todo = [p for p in pairs if p["id"] not in known]
    if todo:
        for p, f in zip(todo, pair_features(todo)):
            known[p["id"]] = [float(v) for v in f]
        if cache:
            Path(cache).write_text(json.dumps(known))
    return {p["id"]: known[p["id"]] for p in pairs}
