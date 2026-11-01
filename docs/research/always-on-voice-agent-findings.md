# Research: Always-On Local Voice Interface for macOS

> Researched 2026-11-01 | about 60 sources consulted | 30 sources cited (see sources.md)

## Executive Summary

No single open-source project combines all three parts:

1. It listens all the time and decides by itself when you talk to it.
2. It routes in about 1 s, with no large model.
3. It navigates and clicks in any app.

Each part exists as a separate component that can run locally on an M4 Pro. Two small MIT projects cover most of the path: **free-mac-voice** and **jev-voice**. Neither one is mature.

The hardest part is the decision "is this speech for the computer?". This is called device-directed speech detection (DDSD). Apple published papers on it, but released no weights. The only working detector found is Attention Labs SAA, and it runs only as a hosted cloud service. Every open project uses a wake word instead, or treats all speech as a command.

The rest is solved well enough to build:
- **Speech to text:** streaming models of 0.6B parameters or smaller run on Apple Silicon.
- **Routing:** tiered routing (a rule match, then an embedding classifier, then a model of about 270M parameters) handles fixed choices in milliseconds.
- **Navigation:** the macOS Accessibility (AX) API plus Apple Vision text recognition (OCR) covers navigation and clicks in any app, without a script for each app.

## Key Findings

### 1. Existing projects (closest first)

| Project | Always-on | "For me?" detection | Routing | Clicks by label | Local | Licence / stars |
|---|---|---|---|---|---|---|
| free-mac-voice | Yes (VAD + wake word "Mac") | Wake word only; the author's test woke on 6 of 10 TV lines | Rule match 0.3 ms → embedding classifier 2 ms → Qwen3-VL 1.3 s | Yes (AX + OCR) | Yes | MIT / 0 |
| jev-voice | Yes (`--always-on`) | None: every utterance is a command | One call to hosted "Jev" per utterance | Experimental (AX table, model picks) | whisper.cpp local; Jev is cloud | MIT / 130 |
| attenlabs saa-sdk | Yes, no wake word | **Yes**: silent, human-directed or device-directed | None | No | Cloud only | SDK Apache-2.0 / 128 |
| Talon Voice | Sleep/wake modes | None | Fixed grammar, no model | Browser hints (Rango); native apps through a mouse grid | Yes | Closed core, free tier |
| macOS Voice Control | Yes | None | Fixed commands | **Yes**: "Click Send", "Show numbers" | Built in | Apple |

**Confidence**: single-source (README claims; no independent tests)

### 2. "Is this speech for me?": no open model exists

- The Apple DDSD papers reached 7.9% equal error rate (EER) with a 7B model and no released weights. The SAS paper (2026) reports a model under 20 MB and under 150 ms, also with no release.
- The open building blocks are:
  - Silero VAD: about 2 MB, MIT licence.
  - Pipecat Smart Turn v3, which detects the end of a turn: about 8 MB, about 12 ms, BSD-2 licence.
  - ECAPA or CAM++ speaker embeddings in CoreML, which accept only your voice.
- Practical recipe: VAD → end of turn → owner-voice check → speech to text → transcript gate. The gate passes a command if it starts with an app name or verb ("Slack…", "click…", "go to…"). Otherwise a small classifier decides, using the front app and whether a call is active. Log false triggers for a week, then tune the thresholds.

**Confidence**: confirmed (absence of open DDSD weights); vendor claims for latency

### 3. Speech to text

| Model | Size | Speed (vendor) | Languages | Licence |
|---|---|---|---|---|
| Parakeet TDT 0.6B v3 (FluidAudio CoreML) | 0.6B | 110–210× real time on M4 Pro (batch) | 25 European; **no Hindi** | Apache-2.0 / CC-BY-4.0 |
| Nemotron-3.5-ASR-Streaming-0.6B | 0.6B | No Mac figure; 80 ms–1.12 s chunks | 40 locales, including Hindi (word error rate 8.0 at 160 ms) | OpenMDW-1.1 |
| Moonshine v2 small (streaming) | 123M | 73 ms from end of speech | English only | MIT |

For Hinglish, the community has Nemotron fine-tunes, which were not verified. Measure end-of-speech latency on the M4 Pro yourself, because no source measured it.

**Confidence**: vendor claims; Hindi WER confirmed on model card

### 4. Router ("System 1")

- **Tier 0:** a rule match (regex or grammar) on app and verb prefixes. Under 1 ms.
- **Tier 1:** an embedding classifier for intent, plus fuzzy match of contact names against Contacts. A few ms. free-mac-voice measured 2 ms.
- **Tier 2:** FunctionGemma 270M, fine-tuned on a few hundred of your own utterances. Google reports that fine-tuning raised accuracy from 58% to 85% on a comparable task. Gemma licence terms apply. A further option is a call to Jev.

**Confidence**: single-source

### 5. Navigation and clicks without a script for each app

Use one data table, with one row for each app:
- the bundle ID
- the deep-link template (`slack://user?team=&id=`, `tg://resolve?domain=&text=`, and `wa.me`/`sms:`/`mailto:`, which are unverified)
- the quick-switcher key (often Cmd+K)

Then run one generic **AX focus heuristic**: a depth-limited search of the focused window for the lowest, widest editable field. Set `AXManualAccessibility` first for Electron apps. You add an app by adding a row, not by writing code.

**Clicks:**
1. Collect buttons, links and rows from the frontmost window's AX tree.
2. Fuzzy-match the spoken label to the element names, then press the match. The match itself takes microseconds.
3. For "second email", sort the rows by position on screen.
4. If no label matches, run Apple Vision OCR. It takes about 130–230 ms on M-series chips.
5. Draw number hints on the same element list for "click 3".

**AX call cost:** under 1 ms on native apps and about 10–50 ms on Electron apps (an estimate). Never walk the full tree of an Electron app.

**Libraries:** AXorcist (MIT, active Oct 2026) and Peekaboo (MIT, 5.4k stars) in Swift. Hammerspoon `hs.axuielement` is the fast prototype option.

**Confidence**: confirmed for libraries and OCR timing; estimate for Electron AX cost

## Contradictions and Open Questions

- The two Parakeet speed figures conflict (110× and 210×). Both are batch numbers, not time to final text.
- TEN VAD beats Silero by its own benchmark, but a third party found it worse on clips with only noise.
- No source measured: end-of-speech latency on M4 Pro, the speed of FunctionGemma on MLX, or the AX tree query time for Slack.
- Open question: the false-trigger rate of a transcript gate without a wake word. Only a real week of use can answer it.

## Methodology

Wave 1 used three agents (Apple, commercial, open source). Wave 2 used four agents: existing projects, directed-speech models, ASR and routers, and UI navigation. The scope then grew to include voice clicking. The agents used WebSearch, WebFetch of READMEs and model cards, and the GitHub API for dates. Most latency figures are vendor claims.
