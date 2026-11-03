"""Query by example: match the owner's own enrolment takes against the live encoder frames.

Each enrolment take is a template: a short sequence of encoder frames (40 ms each).
A streaming subsequence DTW (dynamic time warping) finds, at each new frame, the best match of
each template that ends at that frame. The score is the mean cosine distance along the match
path (0 = same sound, 1 = unrelated). Steps per stream frame: next template frame, the same
template frame (slower speech) or skip one template frame (faster speech).
"""
from __future__ import annotations

import numpy as np
from numba import njit


def normalize(x: np.ndarray, mean: np.ndarray | None = None) -> np.ndarray:
    x = x.astype(np.float32)
    if mean is not None:
        x = x - mean
    return x / (np.linalg.norm(x, axis=1, keepdims=True) + 1e-6)


@njit(cache=True)
def _dtw_stream(cost, starts, lens, penalty, max_stay):
    """cost: (T, N) cosine distances, templates concatenated along N.
    Returns score (K, T) and path length (K, T); inf where no full match ends."""
    T = cost.shape[0]
    K = len(starts)
    score = np.full((K, T), np.inf, dtype=np.float32)
    plen = np.zeros((K, T), dtype=np.int32)
    for k in range(K):
        s0 = starts[k]
        n = lens[k]
        Dp = np.full(n, np.inf, dtype=np.float64)
        Lp = np.zeros(n, dtype=np.int32)
        Sp = np.zeros(n, dtype=np.int32)  # consecutive stays
        D = np.full(n, np.inf, dtype=np.float64)
        L = np.zeros(n, dtype=np.int32)
        S = np.zeros(n, dtype=np.int32)
        for t in range(T):
            D[0] = cost[t, s0]
            L[0] = 1
            S[0] = 0
            for i in range(1, n):
                c = cost[t, s0 + i]
                best = np.inf
                bl = 0
                bs = 0
                # diagonal
                if Dp[i - 1] < np.inf:
                    v = (Dp[i - 1] + c) / (Lp[i - 1] + 1)
                    if v < best:
                        best = v; bl = Lp[i - 1] + 1; bs = 0
                # stay on the same template frame (stream is slower)
                if Dp[i] < np.inf and Sp[i] < max_stay:
                    v = (Dp[i] + c + penalty) / (Lp[i] + 1)
                    if v < best:
                        best = v; bl = Lp[i] + 1; bs = Sp[i] + 1
                # skip one template frame (stream is faster)
                if i >= 2 and Dp[i - 2] < np.inf:
                    v = (Dp[i - 2] + c + penalty) / (Lp[i - 2] + 1)
                    if v < best:
                        best = v; bl = Lp[i - 2] + 1; bs = 0
                if best < np.inf:
                    D[i] = best * bl
                    L[i] = bl
                    S[i] = bs
                else:
                    D[i] = np.inf
                    L[i] = 0
                    S[i] = 0
            score[k, t] = D[n - 1] / L[n - 1] if L[n - 1] > 0 else np.inf
            plen[k, t] = L[n - 1]
            for i in range(n):
                Dp[i] = D[i]; Lp[i] = L[i]; Sp[i] = S[i]
    return score, plen


class Templates:
    def __init__(self, templates: list[np.ndarray], penalty: float = 0.05, max_stay: int = 3):
        self.t = [np.ascontiguousarray(t, dtype=np.float32) for t in templates]
        self.all = np.concatenate(self.t)
        self.lens = np.array([len(t) for t in self.t], dtype=np.int64)
        self.starts = np.concatenate([[0], np.cumsum(self.lens)[:-1]]).astype(np.int64)
        self.penalty = penalty
        self.max_stay = max_stay

    def scores(self, stream: np.ndarray, block: int = 20000):
        """stream: normalized frames (T, D). Returns (K, T) scores and path lengths."""
        if len(stream) == 0:
            return np.zeros((len(self.t), 0), np.float32), np.zeros((len(self.t), 0), np.int32)
        cost = (1.0 - stream @ self.all.T).astype(np.float32)
        return _dtw_stream(cost, self.starts, self.lens, self.penalty, self.max_stay)


def combine(score: np.ndarray, how: str = "best2") -> np.ndarray:
    """One score per frame from the K template scores."""
    s = np.sort(score, axis=0)
    if how == "min":
        return s[0]
    if how == "best2":
        return s[:2].mean(axis=0)
    if how == "best3":
        return s[:3].mean(axis=0)
    if how == "mean":
        return s.mean(axis=0)
    raise ValueError(how)


def detections(s: np.ndarray, theta: float, wait: int = 3, refractory: int = 38) -> list[int]:
    """Frames where the score is below theta and is the lowest of the next `wait` frames.
    After a detection, the next one comes at least `refractory` frames (1.5 s) later."""
    out = []
    t = 0
    T = len(s)
    below = np.nonzero(s < theta)[0]
    j = 0
    last = -10**9
    while j < len(below):
        t = below[j]
        if t - last < refractory:
            j += 1
            continue
        end = min(T, t + wait + 1)
        tm = t + int(np.argmin(s[t:end]))
        # move to the local minimum
        while tm + 1 < T and s[tm + 1] < s[tm] and tm - t < 12:
            tm += 1
        out.append(tm)
        last = tm
        j = np.searchsorted(below, tm + refractory)
    return out


@njit(cache=True)
def _dtw_stream_worst(cost, starts, lens, penalty, max_stay, win):
    """As _dtw_stream, and also the worst part of each match: the highest mean cost of `win`
    template frames in a row along the path (a whole syllable that does not match)."""
    T = cost.shape[0]
    K = len(starts)
    score = np.full((K, T), np.inf, dtype=np.float32)
    worst = np.full((K, T), np.inf, dtype=np.float32)
    for k in range(K):
        s0 = starts[k]
        n = lens[k]
        Dp = np.full(n, np.inf); Lp = np.zeros(n, np.int32); Sp = np.zeros(n, np.int32)
        Mp = np.zeros(n); Wp = np.zeros((n, win))  # last `win` costs on the path, ring
        D = np.full(n, np.inf); L = np.zeros(n, np.int32); S = np.zeros(n, np.int32)
        M = np.zeros(n); Wn = np.zeros((n, win))
        for t in range(T):
            D[0] = cost[t, s0]; L[0] = 1; S[0] = 0; M[0] = 0.0
            for w in range(win):
                Wn[0, w] = cost[t, s0]
            for i in range(1, n):
                c = cost[t, s0 + i]
                best = np.inf; bl = 0; bs = 0; src = -1
                if Dp[i - 1] < np.inf:
                    v = (Dp[i - 1] + c) / (Lp[i - 1] + 1)
                    if v < best:
                        best = v; bl = Lp[i - 1] + 1; bs = 0; src = i - 1
                if Dp[i] < np.inf and Sp[i] < max_stay:
                    v = (Dp[i] + c + penalty) / (Lp[i] + 1)
                    if v < best:
                        best = v; bl = Lp[i] + 1; bs = Sp[i] + 1; src = i
                if i >= 2 and Dp[i - 2] < np.inf:
                    v = (Dp[i - 2] + c + penalty) / (Lp[i - 2] + 1)
                    if v < best:
                        best = v; bl = Lp[i - 2] + 1; bs = 0; src = i - 2
                if src >= 0:
                    D[i] = best * bl; L[i] = bl; S[i] = bs
                    # shift the window of path costs and add this one
                    m = 0.0
                    for w in range(win - 1):
                        Wn[i, w] = Wp[src, w + 1]
                        m += Wn[i, w]
                    Wn[i, win - 1] = c
                    m = (m + c) / win
                    M[i] = Mp[src] if Mp[src] > m else m
                else:
                    D[i] = np.inf; L[i] = 0; S[i] = 0; M[i] = 0.0
            if L[n - 1] > 0:
                score[k, t] = D[n - 1] / L[n - 1]
                worst[k, t] = M[n - 1]
            for i in range(n):
                Dp[i] = D[i]; Lp[i] = L[i]; Sp[i] = S[i]; Mp[i] = M[i]
                for w in range(win):
                    Wp[i, w] = Wn[i, w]
    return score, worst


def scores_worst(T: "Templates", stream: np.ndarray, win: int = 5):
    cost = (1.0 - stream @ T.all.T).astype(np.float32)
    return _dtw_stream_worst(cost, T.starts, T.lens, T.penalty, T.max_stay, win)
