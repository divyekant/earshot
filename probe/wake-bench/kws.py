"""Streaming runs of the icefall KWS Zipformer (gigaspeech, 3.3M) in ONNX.

The same model is in earshot as Core ML (app/Sources/EarshotWake). This module gives:
- encoder frames in joiner space (320-dim, one frame each 40 ms), the same frames that the
  Swift `StreamingSession.frameSink` gives;
- greedy token decoding, the same as `TokenReader` in Swift.
"""
from __future__ import annotations

import os
import numpy as np
import onnxruntime as ort
import kaldi_native_fbank as knf
from paths import DATA

KWS_DIR = os.path.join(DATA, "kws")
ENC = "encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
DEC = "decoder-epoch-12-avg-2-chunk-16-left-64.onnx"
JOI = "joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
RATE = 16000
FRAME_S = 0.04  # one encoder frame


def _session(name: str) -> ort.InferenceSession:
    so = ort.SessionOptions()
    so.intra_op_num_threads = 1
    so.inter_op_num_threads = 1
    return ort.InferenceSession(os.path.join(KWS_DIR, name), so, providers=["CPUExecutionProvider"])


class Kws:
    def __init__(self) -> None:
        self.enc = _session(ENC)
        self.dec = _session(DEC)
        self.joi = _session(JOI)
        meta = self.enc.get_modelmeta().custom_metadata_map
        self.T = int(meta["T"])
        self.shift = int(meta["decode_chunk_len"])
        self.in_names = [i.name for i in self.enc.get_inputs()]
        self.out_names = [o.name for o in self.enc.get_outputs()]
        self.state_shapes = []
        for i in self.enc.get_inputs()[1:]:
            shape = [1 if not isinstance(d, int) else d for d in i.shape]
            dtype = np.int64 if i.type == "tensor(int64)" else np.float32
            self.state_shapes.append((i.name, shape, dtype))
        self.tokens = {}
        with open(os.path.join(KWS_DIR, "tokens.txt"), encoding="utf-8") as f:
            for line in f:
                tok, idx = line.rsplit(maxsplit=1)
                self.tokens[int(idx)] = tok
        self.blank = 0
        self._dec_cache: dict[tuple[int, int], np.ndarray] = {}

    # --- features -------------------------------------------------------------------------
    @staticmethod
    def fbank(samples: np.ndarray) -> np.ndarray:
        opts = knf.FbankOptions()
        opts.frame_opts.samp_freq = RATE
        opts.frame_opts.dither = 0
        opts.frame_opts.snip_edges = False
        opts.mel_opts.num_bins = 80
        opts.mel_opts.low_freq = 20
        opts.mel_opts.high_freq = -400
        fb = knf.OnlineFbank(opts)
        fb.accept_waveform(RATE, samples.astype(np.float32).tolist())
        fb.input_finished()
        n = fb.num_frames_ready
        return np.stack([fb.get_frame(i) for i in range(n)]) if n else np.zeros((0, 80), np.float32)

    def init_states(self) -> list[np.ndarray]:
        return [np.zeros(shape, dtype) for _, shape, dtype in self.state_shapes]

    def encode(self, samples: np.ndarray, tail_pad_s: float = 0.5) -> np.ndarray:
        """All encoder frames (n, 320) of a clip, streaming, from a fresh state.
        Silence is added at the end so that the last chunk is complete (the app gets more audio)."""
        audio = np.concatenate([samples.astype(np.float32), np.zeros(int(tail_pad_s * RATE), np.float32)])
        feats = self.fbank(audio)
        states = self.init_states()
        out = []
        start = 0
        while start + self.T <= len(feats):
            x = feats[start:start + self.T][None].astype(np.float32)
            res = self.enc.run(None, {"x": x, **{n: s for (n, _, _), s in zip(self.state_shapes, states)}})
            out.append(res[0][0])
            states = res[1:]
            start += self.shift
        return np.concatenate(out) if out else np.zeros((0, 320), np.float32)

    # --- decoding -------------------------------------------------------------------------
    def dec_out(self, ctx: tuple[int, int]) -> np.ndarray:
        if ctx not in self._dec_cache:
            self._dec_cache[ctx] = self.dec.run(None, {"y": np.array([ctx], np.int64)})[0][0]
        return self._dec_cache[ctx]

    def logits(self, frames: np.ndarray, ctx: tuple[int, int]) -> np.ndarray:
        d = np.repeat(self.dec_out(ctx)[None], len(frames), axis=0)
        return self.joi.run(None, {"encoder_out": frames.astype(np.float32), "decoder_out": d})[0]

    def greedy(self, frames: np.ndarray) -> list[str]:
        """Greedy transducer decoding, one token at most per frame (as TokenReader in Swift)."""
        ctx = (self.blank, self.blank)
        out = []
        for f in frames:
            lg = self.logits(f[None], ctx)[0]
            best = int(np.argmax(lg))
            if best == self.blank:
                continue
            out.append(self.tokens[best])
            ctx = (ctx[1], best)
        return out
