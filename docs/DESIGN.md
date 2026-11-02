# earshot design (proposed)

This design is a proposal. Phase 0 measurements can change it. Each section names the requirements it covers (see REQUIREMENTS.md).

## 1. Pipeline

```
mic ─► [1 Audio gate] ─► [2 Speech to text] ─► [3 "For me?" gate] ─► [4 Router] ─► [5 Actions] ─► [6 Feedback]
         VAD                streaming ASR         rules + classifier     rules →        navigate /
         end of turn                                                     embeddings →   focus / type /
         owner voice                                                     tiny model     click
```

## 2. Latency budget (R-SP-1, R-SP-3)

| Stage | Target |
|---|---|
| End of turn detected | 100–200 ms after speech stops |
| Final transcript | 100–300 ms |
| "For me?" gate + router | under 50 ms (tiers 0–1); under 300 ms (tier 2) |
| Open app + conversation | 100–400 ms (deep link or quick switcher) |
| Focus text box (accessibility) | under 100 ms native; under 300 ms Electron |
| **Total to focused box** | **about 1 s** |
| Voice click (label match) | under 500 ms total |

E0 measured these stages on this Mac (see [experiments/E0-viability.md](experiments/E0-viability.md), sections 5 and 6). Voice commands: median 582 ms from key release to focused box. Final transcript: 23 to 101 ms. Slack switcher (Command-K, name, Return): about 400 ms, including a fixed 250 ms wait. Focus after the chat opens: about 100 ms. The owner's goal is about 100 ms in total, so the next work is on the switcher step and on the wait for held keys.

## 3. Components

### 3.1 Audio gate (R-ON-1, R-ON-3)

| Part | Proposed component | Notes |
|---|---|---|
| Voice activity detection (VAD) | Silero VAD (about 2 MB, MIT) | Also test TEN VAD on the owner's own audio. |
| End of turn | Pipecat Smart Turn v3 (about 8 MB, BSD-2) | Runs only after the VAD reports silence. Vendor latency is about 12 ms. |
| Owner voice check | ECAPA-TDNN or CAM++ speaker embedding (CoreML) | Enroll the owner once. Reject segments below a tuned cosine score. |

Swift SDKs: FluidAudio and speech-swift bundle these parts.

### 3.2 Speech to text (R-MD-1, R-MD-5)

| Option | Use when |
|---|---|
| Apple SpeechTranscriber (Speech framework, macOS 26 and later) | First choice for English. It is built into macOS and runs on the device. macOS manages the model, so earshot ships no speech model. It accepts name hints (`AnalysisContext.contextualStrings`). E0: 14 of 14 commands heard correctly, final text 23 to 101 ms after key release. |
| Parakeet TDT 0.6B v3 (CoreML through FluidAudio) | English only. It does not support Hindi. |
| Nemotron-3.5-ASR-Streaming-0.6B (speech-swift) | English and Hindi. Hindi word error rate is 8.0 at 160 ms chunks (model card). Test the Hinglish fine-tunes. |
| Moonshine v2 small (MIT, 123M) | Fastest English-only option. The vendor reports 73 ms. |

No source measured end-of-speech latency on an M4 Pro. Measure it in Phase 0.

### 3.3 "Is this for me?" gate (R-ON-2, R-ON-5)

No open model for device-directed speech detection (DDSD) exists. Apple's work is paper-only, and Attention Labs SAA is cloud-only. Build the gate in layers:

1. **Prefix rule.** A transcript that starts with a known app name, verb or command word passes at once. Examples: "Slack…", "click…", "go to…", "show numbers".
2. **Follow-up window.** For a few seconds after a command, accept speech without a prefix, for example the dictated message text.
3. **Context.** If a call app has the microphone, require the prefix.
4. **Classifier.** A small text classifier for other cases. Train it on the logs from Phase 3.
5. **Safety.** Actions that cannot be undone, such as Send, need an explicit spoken command. A false trigger can only focus, open or type.

### 3.4 Router: "System 1" (R-SP-2, R-MD-2)

| Tier | Method | Speed |
|---|---|---|
| 0 | Rule match on app names, verbs and grammar | under 1 ms |
| 1 | Sentence embedding + nearest intent; fuzzy match of names against Contacts and per-app caches | a few ms |
| 2 | FunctionGemma 270M, fine-tuned on a few hundred of the owner's commands, through MLX | measure in Phase 0 |

Output: one action with arguments, for example `{action: "message", app: "slack", target: "Ravi", text: "running late"}`.

free-mac-voice (MIT) already uses the same tiers. Read its code before you write the router.

### 3.5 Actions (R-NV-*, R-CL-*, R-MT-*)

**App table.** Keep one data file, for example `apps.yaml`, with one row for each app:

```yaml
- app: slack
  bundle_id: com.tinyspeck.slackmacgap
  open_target:
    deep_link: "slack://user?team={team_id}&id={user_id}"   # needs a name-to-ID cache
    quick_switcher: "cmd+k"                                 # fallback: type name, Return
  electron: true
- app: telegram
  bundle_id: ru.keepcoder.Telegram
  open_target:
    deep_link: "tg://resolve?domain={username}&text={text}"
```

Verify the deep-link formats for WhatsApp, Messages and Discord. The research did not confirm them.

E0 used each app's own search in place of links, so the owner gives names only. Slack: Command-K. Messages: File > New Message (Command-N) and the "To:" field. WhatsApp (left out of E0): Command-F; the search also lists message hits, so a later design must check the type of the top result before Return.

**Generic focus.** Run a depth-limited accessibility search of the focused window. Find the lowest and widest editable element (`AXTextArea`, `AXTextField`, or an editable web area), then focus it. For Electron apps, first set `AXManualAccessibility`, then poll `AXChildren` for up to 200 ms. Never walk the full tree of an Electron app.

**Type text.** Set the accessibility value, or paste through the clipboard and restore the clipboard afterwards.

**Click.**
1. Collect buttons, links, menu items and rows from the front window.
2. Fuzzy-match the spoken label to `AXTitle`, `AXDescription` and `AXValue`, then press the match.
3. For ordinal commands ("second email"), sort the rows by position on screen.
4. If no label matches, run Apple Vision OCR (about 130–230 ms) and click the matched text.
5. For "show numbers", draw numbered labels over the same element list.

Libraries: AXorcist (MIT) for accessibility. Peekaboo (MIT) is a reference for the user-interface map and background input.

### 3.6 Feedback (R-FB-*)

Show a small overlay near the menu bar, for example "→ Slack · Ravi" or "✗ not for me". Spoken replies are off by default.

### 3.7 Optional text cleanup

The oMLX server can clean up dictated text: punctuation and filler words. Make it optional, because it adds latency.

## 4. Permissions

- Microphone
- Accessibility
- Screen Recording (only for the OCR fallback)

## 5. Phase plan

### Phase 0: Measure (do this first)

E0 replaces step 1 below. E0 measures the speech, focus and total times directly, with no setup of other projects. Read the code of free-mac-voice and jev-voice as reference only. See [experiments/E0-viability.md](experiments/E0-viability.md).

1. Clone free-mac-voice and jev-voice, and run them. Record:
   - speed
   - false triggers
   - which parts can be reused
2. Measure, on this Mac:
   - end-of-speech to final transcript for Parakeet v3, Nemotron-3.5 streaming and Moonshine small
   - FunctionGemma 270M on MLX: time to first token and total time for about 20 tokens
   - accessibility search time for the composer in Slack, WhatsApp, Messages and Mail
   - Apple Vision OCR time on a full window
3. Write the results to `docs/research/phase0-measurements.md`. Update DESIGN.md if a result changes a decision.

### Phase 1: Push-to-talk MVP

One key, then speech, then routing (tiers 0–1), then navigation through the app table and generic focus, then typing. Support Slack, WhatsApp, Messages and Mail.

### Phase 2: Voice clicks

Label match, ordinal match, number hints, OCR fallback.

### Phase 3: Always on

Add the audio gate and the "for me?" gate (prefix rule, follow-up window, call context). Log every trigger and every rejection for one week.

### Phase 4: Learn

Fine-tune the gate classifier and the tier-2 router on the Phase 3 logs. Add Hinglish support if Phase 0 found a usable model.

## 6. Existing projects to study

| Project | Licence | What to take |
|---|---|---|
| free-mac-voice | MIT | Tiered router, accessibility + OCR clicks |
| jev-voice | MIT | Always-on loop, accessibility element table |
| AXorcist, Peekaboo | MIT | Accessibility library, user-interface map |
| FluidAudio, speech-swift | Apache-2.0 (check model terms) | VAD, ASR, turn detection, speaker embeddings in Swift |
| Talon + Rango | Closed core + MIT | Command grammar and click-hint ideas |
| macOS Voice Control | Apple | Reference behavior for "click <name>" and "show numbers" |
