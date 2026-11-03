"""Python port of the earshot keyword decoder (Swift StreamingKwsDecoder + ContextGraph, from
soniqo/speech-swift a57702e), so that the bench runs the current method on cached encoder frames.

The joiner is output_linear(tanh(enc + dec)). Its int8 weights are read from the ONNX file and
used in float, so one frame for all beam paths is one small matrix product.
"""
from __future__ import annotations

import math
import os
from dataclasses import dataclass, field

import numpy as np
import onnx
from onnx import numpy_helper

from kws import KWS_DIR, JOI, Kws


def joiner_weights() -> tuple[np.ndarray, np.ndarray]:
    m = onnx.load(os.path.join(KWS_DIR, JOI))
    init = {i.name: numpy_helper.to_array(i) for i in m.graph.initializer}
    w = (init["output_linear.weight_quantized"].astype(np.float32)
         - float(init["output_linear.weight_zero_point"])) * float(init["output_linear.weight_scale"])
    return w.astype(np.float32), init["output_linear.bias"].astype(np.float32)


# --- context graph (Aho-Corasick), the same rules as ContextGraph.swift ---------------------
class State:
    __slots__ = ("id", "token", "token_score", "node_score", "output_score", "is_end", "level",
                 "phrase", "ac_threshold", "next", "fail", "output")

    def __init__(self, id, token, token_score, node_score, output_score, is_end, level, phrase="", ac=1.0):
        self.id = id; self.token = token; self.token_score = token_score; self.node_score = node_score
        self.output_score = output_score; self.is_end = is_end; self.level = level; self.phrase = phrase
        self.ac_threshold = ac; self.next = {}; self.fail = None; self.output = None


class ContextGraph:
    def __init__(self, context_score: float = 0.5, ac_threshold: float = 0.15):
        self.context_score = context_score
        self.ac_threshold = ac_threshold
        self.root = State(0, -1, 0, 0, 0, False, 0)
        self.root.fail = self.root
        self.n = 0

    def build(self, token_ids, phrases, boosts, thresholds):
        for tokens, phrase, b, th in zip(token_ids, phrases, boosts, thresholds):
            if not tokens:
                continue
            score = self.context_score if b == 0 else b
            thr = self.ac_threshold if th == 0 else th
            node = self.root
            for i, tok in enumerate(tokens):
                is_end = i == len(tokens) - 1
                if tok in node.next:
                    ex = node.next[tok]
                    ex.token_score = max(score, ex.token_score)
                    ex.node_score = node.node_score + ex.token_score
                    comb = ex.is_end or is_end
                    ex.output_score = ex.node_score if comb else 0
                    ex.is_end = comb
                    if is_end:
                        ex.phrase = phrase; ex.ac_threshold = thr
                    node = ex
                else:
                    self.n += 1
                    ns = node.node_score + score
                    new = State(self.n, tok, score, ns, ns if is_end else 0, is_end, i + 1,
                                phrase if is_end else "", thr if is_end else 0.0)
                    node.next[tok] = new
                    node = new
        self._fill()
        return self

    def _fill(self):
        queue = []
        for node in self.root.next.values():
            node.fail = self.root
            queue.append(node)
        c = 0
        while c < len(queue):
            cur = queue[c]; c += 1
            for tok, node in cur.next.items():
                fail = cur.fail or self.root
                if tok in fail.next:
                    fail = fail.next[tok]
                else:
                    fail = fail.fail or self.root
                    while tok not in fail.next:
                        if fail.token == -1:
                            break
                        fail = fail.fail or self.root
                    if tok in fail.next:
                        fail = fail.next[tok]
                node.fail = fail
                out = node.fail
                while out is not None and not out.is_end:
                    if out.fail is not None and out.fail.token != -1:
                        out = out.fail
                    else:
                        out = None
                        break
                node.output = out
                node.output_score += out.output_score if out is not None else 0
                queue.append(node)

    def forward(self, state: State, token: int):
        if token in state.next:
            node = state.next[token]
            score = node.token_score
        else:
            fail = state.fail or self.root
            while token not in fail.next:
                if fail.token == -1:
                    break
                fail = fail.fail or self.root
            node = fail.next.get(token, fail)
            score = node.node_score - state.node_score
        return score + node.output_score, node

    @staticmethod
    def matched(state: State):
        if state.is_end:
            return state
        return state.output


@dataclass
class Hyp:
    ys: tuple
    log_prob: float
    ac_probs: list = field(default_factory=list)
    timestamps: list = field(default_factory=list)
    state: State = None
    trailing: int = 0


class KwsDecoder:
    """Streaming modified beam search with keyword boosting (beam 4, 1 trailing blank, 1.5 s reset)."""

    def __init__(self, kws: Kws, graph: ContextGraph, beam: int = 4, trailing_blanks: int = 1,
                 auto_reset_s: float = 1.5, W=None, b=None):
        self.kws = kws
        self.g = graph
        self.beam = beam
        self.trailing_blanks = trailing_blanks
        self.auto_reset = max(1, round(auto_reset_s / 0.04))
        self.W, self.b = (W, b) if W is not None else joiner_weights()
        self.dec_cache: dict[tuple, np.ndarray] = {}
        self.reset()

    def dec(self, ys: tuple) -> np.ndarray:
        ctx = ys[-2:]
        if ctx not in self.dec_cache:
            # The decoder sees -1 at the start; the ONNX decoder needs an id, use blank (0).
            self.dec_cache[ctx] = self.kws.dec_out(tuple(max(0, t) for t in ctx))
        return self.dec_cache[ctx]

    def reset(self):
        self.t = 0
        self.since = 0
        self.beam_list = [Hyp(ys=(-1, 0), log_prob=0.0, state=self.g.root)]

    def step(self, frame: np.ndarray):
        """One encoder frame. Returns (phrase, timestamps, frame index) or None."""
        hyps = self.beam_list
        d = np.stack([self.dec(h.ys) for h in hyps])
        logits = np.tanh(frame[None] + d) @ self.W + self.b
        m = logits.max(axis=1, keepdims=True)
        e = np.exp(logits - m)
        s = e.sum(axis=1, keepdims=True)
        probs = e / s
        logp = np.log(np.maximum(probs, 1e-38))
        total = logp + np.array([h.log_prob for h in hyps])[:, None]
        flat = total.ravel()
        k = min(self.beam, flat.size)
        idx = np.argpartition(-flat, k - 1)[:k]
        idx = idx[np.lexsort((idx, -flat[idx]))]  # by score, then by enumeration order
        V = logits.shape[1]
        nxt: dict[tuple, Hyp] = {}
        for j in idx:
            hi, tok = divmod(int(j), V)
            h = hyps[hi]
            ys, acp, ts, st, tr = h.ys, h.ac_probs, h.timestamps, h.state, h.trailing + 1
            cs = 0.0
            if tok != 0:
                ys = ys + (tok,)
                ts = ts + [self.t]
                acp = acp + [float(probs[hi, tok])]
                cs, st = self.g.forward(st, tok)
                tr = 0
                if st.token == -1:
                    ys = ys[:-2] + (-1, 0)
            lp = float(flat[j]) + cs
            if ys in nxt:
                ex = nxt[ys]
                a, bb = ex.log_prob, lp
                mm = max(a, bb)
                ex.log_prob = mm + math.log1p(math.exp(-abs(a - bb)))
            else:
                nxt[ys] = Hyp(ys, lp, acp, ts, st, tr)
        self.beam_list = list(nxt.values())
        top = max(self.beam_list, key=lambda h: h.log_prob / max(len(h.ys), 1))
        mt = ContextGraph.matched(top.state)
        if mt is not None and mt.level > 0 and len(top.ac_probs) >= mt.level:
            ac = sum(top.ac_probs[-mt.level:]) / mt.level
            if top.trailing > self.trailing_blanks and ac >= mt.ac_threshold:
                hit = (mt.phrase, top.timestamps[-mt.level:], self.t, ac)
                self.reset()
                self.t += 1
                self.since = 0
                return hit
        self.t += 1
        self.since += 1
        if self.since >= self.auto_reset:
            t = self.t
            self.reset()
            self.t = t
        return None

    def run(self, frames: np.ndarray, offset: int = 0):
        """All hits in a frame sequence: list of (frame index of the hit, phrase, ac score, first stamp)."""
        out = []
        for i, f in enumerate(frames):
            h = self.step(f)
            if h is not None:
                out.append((offset + i, h[0], h[3], offset + i - (h[2] - h[1][0])))
        return out


def graph_for(kws_model, specs) -> ContextGraph:
    """specs: list of (pieces list, boost, threshold, label)."""
    tok2id = {v: k for k, v in kws_model.tokens.items()}
    g = ContextGraph(context_score=0.5, ac_threshold=0.15)
    g.build([[tok2id[p] for p in s[0]] for s in specs], [s[3] for s in specs],
            [s[1] for s in specs], [s[2] for s in specs])
    return g
