# earshot design (proposed)

This design is a proposal. Phase 0 measurements can change it. Each section names the requirements it covers (see REQUIREMENTS.md).

## 1. Pipeline

```
mic ─► [1 Wake gate] ─► [2 Speech to text] ─► [3 Strip the phrase] ─► [4 Router] ─► [5 Actions] ─► [6 Feedback]
        wake phrase       streaming ASR         (always-on only)        rules →        navigate /
        owner voice                                                     embeddings →   focus / type /
        end of turn                                                     tiny model     click
```

With the hold key, the key replaces stages 1 and 3.

## 2. Latency budget (R-SP-1, R-SP-3)

| Stage | Target |
|---|---|
| End of turn detected | 100–200 ms after speech stops |
| Final transcript | 100–300 ms |
| Wake phrase detected (always-on) | 300–500 ms after the phrase; the command can follow at once |
| Router | under 50 ms (tiers 0–1); under 300 ms (tier 2) |
| Open app + conversation | 100–400 ms (deep link or quick switcher) |
| Focus text box (accessibility) | under 100 ms native; under 300 ms Electron |
| **Total to focused box** | **about 1 s** |
| Voice click (label match) | under 500 ms total |

E0 measured these stages on this Mac (see [experiments/E0-viability.md](experiments/E0-viability.md), sections 5 and 6). Voice commands: median 582 ms from key release to focused box. Final transcript: 23 to 101 ms. Slack switcher (Command-K, name, Return): about 400 ms, including a fixed 250 ms wait. Focus after the chat opens: about 100 ms. The owner's goal is about 100 ms in total, so the next work is on the switcher step and on the wait for held keys.

E2 measured voice clicks in Chrome (see [experiments/E2-web-and-speech.md](experiments/E2-web-and-speech.md), section 5.7). From the text to the click: 33 ms median, 122 ms for the slowest 1 in 10 (with the tier-2 model for some commands). With speech, the click occurs about 70 to 90 ms after the end of speech. Chrome then needs about 320 ms to show the new page.

## 3. Components

### 3.0 Targets and verbs (R-MT-1, R-MT-2)

earshot uses one model for all apps. A command is one verb and one target.

**Verbs.** The set of verbs is small and fixed.

| Verb | Intent | Examples |
|---|---|---|
| open | `openApp`, `openURL`, `openChat` | "open Zoom", "open hn.com", "Slack Ravi" |
| press | `click` | "click Notifications", "select all", "click 5" |
| type | `typeText`, `typeInto`, the text of `openChat` | "type see you at five", "search for voice control" |
| scroll | `scroll` | "scroll down", "go to the top" |
| back | `back` | "go back" |
| send | `send` | "send" (hold key only, R-NV-5) |

"Show numbers" and "hide numbers" are display helpers for press.

**Targets.** earshot reads the targets from the apps at run time. It does not keep a list of targets for each app.

| Source | Targets | When earshot reads it |
|---|---|---|
| Screen | Buttons, links, fields and rows of the front window. OCR text if the app gives no labels. | At each command (about 15 to 40 ms) |
| Menus | The enabled menu items of the front app, for example Edit > Select All. A menu item is a press target with the id `m:<path>`. | From a cache. earshot reads it again when an app becomes active, at start and after each command. A command never reads the menus. |
| Chats | Sidebar names, the app's own search, the owner's own chat | From a cache (NameWarmer) |
| Apps and sites | Approved apps, with the names and URL schemes that each app declares. Web addresses. | Catalogue at start |

**Rules for new work.**
1. Do not add a verb or an intent for one app or for one feature. If a command does not work, find the source that holds its target. Then add that source, or fix how earshot reads it.
2. Add a new verb only if no current verb can do the command, for example drag. Record the reason in `docs/DECISIONS.md`.
3. Every target goes through the same matcher and the same safety rules (`SafetyPolicy`), from any source.
4. Facts about one app are data (`apps.json`, `names.json`, `focus-methods.json`). They are never code.

Plain words with no command word are dictation: with the hold key, the pipeline types them into the focused text field (`typeText`), if `ScreenSnapshot.focusedID` names an editable field that is not a password field and the page is not a sign-in, code or payment page. Dictation never presses Return, and always-on mode never dictates. If earshot's own window is in front, the pipeline first brings back the app that was in front before it; earshot's own window is never a target.

### 3.1 Wake gate (R-ON-1, R-ON-2, R-ON-3, D-11)

| Part | Component | Notes |
|---|---|---|
| Wake phrase | icefall KWS Zipformer (gigaspeech, 3.49M parameters, Apache-2.0), Core ML INT8 (`aufklarer/KWS-Zipformer-3M-CoreML-INT8`) | Open vocabulary: the phrase is text, no training. It runs on 320 ms chunks. Vendor time: 5.4 ms for each chunk on Apple silicon. |
| Owner voice check | WeSpeaker ResNet34-LM (VoxCeleb, CC BY 4.0), Core ML (`aufklarer/WeSpeaker-ResNet34-LM-CoreML`) | 256-value embedding. Cosine similarity against the mean of 5 enrolment phrases. Threshold 0.35 (live trial: owner 0.50 to 0.73, another voice 0.06). |
| End of turn | `SpeechDetector` (energy with a noise floor that adapts) | 550 ms of quiet after the command. After the phrase alone, it waits 2 s for the command. |

The code is in `app/Sources/EarshotWake`. The spotter and voice code are copied from soniqo/speech-swift at `a57702e` (Apache-2.0, see THIRD_PARTY_NOTICES.md). The models download one time (about 18 MB) at pinned revisions, with a SHA-256 check, into `~/Library/Application Support/earshot/models/`.

How a command flows (`EarshotInput/WakeTrigger.swift`):

1. The spotter listens to 16 kHz audio. Between turns, nothing else runs. Speech without the phrase never reaches the speech engine.
2. The spotter fires about 0.3 to 0.5 s after the phrase. If a voice is enrolled, the voice model scores the audio of the phrase. A low score stops here, and the log gets one line with no text.
3. The speech engine starts at the start of the phrase. `MicrophoneFeed` keeps 3 s of audio, and `PrerollControl.setNextPreroll` gives the engine the phrase and every word after it.
4. The turn ends after the command. The pipeline removes the phrase, and the router runs as for the hold key.
   - Apple SpeechTranscriber gives the audio time of each word (`.audioTimeRange`). The spotter gives the end of the phrase. The pipeline drops the first words that start more than 0.15 s before the phrase end (`WakePhrase.cut`). The start is the sure edge of a word, and the phrase end from the spotter tends to be a little late. So the spelling of the phrase does not matter ("Yeah, let's" for "hey atlas").
   - Then the text match (`WakePhrase.strip`) removes what the time cut left, for example the last word of the phrase.
   - With no word times (Parakeet, on-device dictation), the text match alone runs. Apple speech can write the phrase as other words ("Here, at least" for "hey atlas"). So at the start of the text, the match may differ in up to half of the letters of the phrase.
   - Apple speech and dictation get the phrase as a hint (`contextualStrings`).
5. For 5 s after a command, speech in the owner's voice starts a turn with no phrase. The voice is checked at the end of the turn. The spotter keeps on for the first 2.5 s of that turn. If the owner says the phrase again, the turn becomes a wake turn: the phrase is cut by time, and the voice of the phrase counts.
6. The spotter clears its state every 1.5 s with no wake (the upstream rule). While a guess is inside the phrase, the reset waits up to 1 s more, so a phrase that falls on the reset point can end.
7. The spotter counts near misses: the top guess matched half of the phrase pieces or more, then fell back with no wake, and no wake came in 1 s. The log gets the count and the best part of the phrase, every 60 s of audio and at each wake. It has no audio and no text.

The enrolment (Manage > General > Teach earshot your voice) records 5 phrases. earshot keeps the mean embedding and, for a made-up name, the word pieces that the spotter heard, in `voice.json`. It keeps no audio.

Limits: the spotter is English only. The voice check is less sure on short audio. A made-up name ("hey earshot") also wakes on sound-alikes ("hey, your shot"). Intel Macs run Core ML on the CPU; measure the speed there.

### 3.2 Speech to text (R-MD-1, R-MD-5)

| Option | Use when |
|---|---|
| Parakeet 0.6B, the model file of Hex (`parakeet-unified-en-0.6b-Q8_0.gguf`, transcribe.cpp on Metal) | Optional, when the owner chooses "Parakeet" in Settings. It is not the default (live test 2026-11-02, below). earshot reads the file in place, so there is no download. E2: 114 of 126 commands routed correctly, 14.9 % word errors, 34 ms median on short commands. It loads in 14.4 s and uses about 890 MB, so it must stay loaded. English only. Weights CC BY 4.0. |
| Apple SpeechTranscriber (Speech framework, macOS 26 and later) | Default ("auto"). It is built into macOS and runs on the device. macOS manages the model, so earshot ships no speech model. E0: 14 of 14 commands heard correctly, final text 23 to 101 ms after key release. E2: 113 of 126 routed correctly, 18.8 % word errors, 56 ms median. It takes name hints (`AnalysisContext.contextualStrings`), but in E2 the hints did not change the text. |
| Apple on-device dictation (`SFSpeechRecognizer`, `requiresOnDeviceRecognition`, macOS 14 and later) | The Apple engine on Intel Macs and on macOS before 26, and the fallback if SpeechTranscriber does not load. It runs on the device and never sends audio to a server. If the Mac cannot recognize the locale on the device, the engine does not start. Latency: measure on the Intel Mac (MacBook Pro 13", 2019, i5-8257U, 8 GB, macOS 15.7). |
| Nemotron-3.5-ASR-Streaming-0.6B (speech-swift) | English and Hindi. Hindi word error rate is 8.0 at 160 ms chunks (model card). Test the Hinglish fine-tunes. |
| Moonshine v2 small (MIT, 123M) | Fastest English-only option. The vendor reports 73 ms. |

No source measured end-of-speech latency on an M4 Pro. Measure it in Phase 0.

E2 (section 6.2) chose Parakeet by a small margin: 1 command in 126, on `say` voices. The live test of the app on 2026-11-02 changed the default to Apple:

| Measure (owner's Mac, memory full: swap 4.5 to 6.7 GB of 5 to 7 GB) | Parakeet | Apple |
|---|---|---|
| Live speech stage, 8 commands in one session | 441, 900, 821, 565, 646, 2567, 2232, 6937 ms | — |
| Replay of `say` commands through the turn path, after key release | 110 to 2000 ms; 20 in a row: median 250 to 570 ms | about 30 ms (first call about 110 ms) |
| 12-file bench, median / p90 | 231 to 281 ms / 552 to 800 ms (E2 with free memory: 33 ms) | 54 to 67 ms / 67 to 123 ms |

- All the Parakeet time was decode. The tail after key release was 1.2 ms or less, and the queue wait 0.4 ms or less. There was no growth over 20 commands.
- macOS moved the 890 MB of Parakeet weights out of memory between commands (the app's resident memory fell from 746 MB to about 100 MB). Each decode then read them back from swap.
- So "auto" uses Apple and does not load Parakeet. The setting "Parakeet" uses Parakeet for a command only when a warm-up run at the key press shows that the weights are in memory and the memory pressure is normal. Else Apple makes the text, so Parakeet never makes the owner wait.
- Each command logs the engine and the reason (`SpeechTiming.why`) and the stages `speech.tail`, `speech.wait` and `speech.decode`.

Both engines miss the same names, so the router must also match names by sound.

### 3.3 "Is this for me?" (R-ON-2, R-ON-5)

The wake phrase decides (D-11). The first design had a text gate with no wake word (a prefix rule, a follow-up window and a call context). It passed common command words in normal talk, and it had no voice check. D-11 removed it.

The safety rule stays: actions that cannot be undone, such as Send, need the hold key. A false wake can only focus, open or type (`ActionRules.sendBlock`).

### 3.4 Router: "System 1" (R-SP-2, R-MD-2)

| Tier | Method | Speed |
|---|---|---|
| 0 | Rule match on app names, verbs and grammar | under 1 ms |
| 1 | Sentence embedding + nearest intent; fuzzy match of names against Contacts and per-app caches | a few ms |
| 2 | FunctionGemma 270M, fine-tuned on a few hundred of the owner's commands, through MLX | measure in Phase 0 |

Output: one action with arguments, for example `{action: "message", app: "slack", target: "Ravi", text: "running late"}`.

free-mac-voice (MIT) already uses the same tiers. Read its code before you write the router.

Measured in E1 (2026-11-02, [E1-generic-router.md](experiments/E1-generic-router.md)): rules with fuzzy match (tiers 0 and 1) were sure for 30 of 42 test commands and correct for all 30, in about 20 ms. For the other 12, one text-only call to Jev (a cloud model, test only, see R-MD-1) picked from a short list in about 90 ms median (568 ms at most). Together: 42 of 42, with no wrong chat. The tier-2 model is still open: the owner plans an own small model, trained on the logs.

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

E1 built the app rows from each app's menu bar, with no row written by hand: the menu item whose title says "switch to", "jump to" or "new message" gives the search keys. For Slack and Messages, the generated rows were the same as the E0 rows. The names come from two sources: the chat list in each app's sidebar (fast, but Slack shows only a few chats to Accessibility), and the app's own search at command time (it knows every chat; 160 to 630 ms).

E0 used each app's own search in place of links, so the owner gives names only. Slack: Command-K. Messages: File > New Message (Command-N) and the "To:" field. WhatsApp (left out of E0): Command-F; the search also lists message hits, so a later design must check the type of the top result before Return.

**Generic focus.** Run a depth-limited accessibility search of the focused window. Find the lowest and widest editable element (`AXTextArea`, `AXTextField`, or an editable web area), then focus it. For Electron apps, first set `AXManualAccessibility`, then poll `AXChildren` for up to 200 ms. Never walk the full tree of an Electron app.

**Type text.** Set the accessibility value, or paste through the clipboard and restore the clipboard afterwards.

**Open a web address (R-NV-7).** The router takes "open", "go to", "visit", "browse to" or "load", followed by words that form a domain name ("hn.com", "news dot ycombinator dot com", "example.org slash docs"). Speech can glue the command word to the address ("Openhnm.com"): the router splits it only when the rest is a domain. The action opens the address in the default browser with `NSWorkspace.open`. It accepts only http and https, because other schemes can start apps. It presses no key.

**Click.**
1. Collect buttons, links, menu items and rows from the front window. In a browser, find the page on screen with a hit test in the front window, and read its visible elements with one `AXUIElementsForSearchPredicate` call (12 ms in E2). Chrome keeps the pages of hidden tabs in the tree, so a page found by a tree search can be a hidden tab.
2. Fuzzy-match the spoken label to `AXTitle`, `AXDescription` and `AXValue`. Numbers must match exactly. Block every label with a risky word (send, pay, delete, submit, vote, star and similar). A title is not a command: a tab button, and a menu item that names an open tab or window of the app (found by data, not by menu names), use the rule of a link. A title is risky only if it has 3 words or fewer and a risky word, or if it starts with a risky word. Bookmarks and History menus are not targets.
3. Act only on a page of the expected app or site. Never act on a sign-in, code or payment page.
4. Press the match with `AXPress` if the element offers it. A Chrome link does not offer it: `AXPress` returns success and does nothing (E2, section 5.6). Else click a point where the top element on screen is the match, and move the pointer back. If no such point exists, scroll the element into view (`AXScrollToVisible`) and try again.
5. For ordinal commands ("second email", "second result"), sort the rows by position on screen. On a web page, a result is a link in a heading.
6. If no label matches, run Apple Vision OCR (about 130–230 ms) and click the matched text.
7. For "show numbers", draw numbered labels over the same element list.
8. Optional, off by default (D-10, "Jev sees the screen"): if no label matches a hold-key click, take one picture of the front window, draw the numbers of step 7 on it, and ask Jev once. Jev picks a number, or else gives a box. For a box, earshot clicks its middle only if the element under the point is of the front app, has a label, and is not risky. The click then goes through steps 3 and 4. Never on a sign-in, code or payment page. The command path asks only after the route, only for a press by the router's verb parse, and only if the route has no sure target and was not blocked. A blocked route never goes to the screenshot. The click runs at the tier `jev`.

E2 measured this in Chrome on 4 public pages: 42 of 43 commands correct, 25 of 25 link clicks changed the page, 0 risky elements pressed.

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

Label match, ordinal match, number hints, OCR fallback. E2 tested the label match and the ordinal match in Chrome (go). Number hints and the OCR fallback are still open.

### Phase 3: Always on

Add the wake gate (wake phrase, owner voice, follow-up window; D-11). Log every wake, every rejected wake and every voice score for one week. Then tune the voice threshold and decide if a trained wake model (livekit-wakeword) is needed.

### Phase 4: Learn

Fine-tune the tier-2 router on the Phase 3 logs. Add Hinglish support if Phase 0 found a usable model.

## 6. Existing projects to study

| Project | Licence | What to take |
|---|---|---|
| free-mac-voice | MIT | Tiered router, accessibility + OCR clicks |
| jev-voice | MIT | Always-on loop, accessibility element table |
| AXorcist, Peekaboo | MIT | Accessibility library, user-interface map |
| FluidAudio, speech-swift | Apache-2.0 (check model terms) | VAD, ASR, turn detection, speaker embeddings in Swift |
| Talon + Rango | Closed core + MIT | Command grammar and click-hint ideas |
| macOS Voice Control | Apple | Reference behavior for "click <name>" and "show numbers" |
| Hex (anomalyco/hex) | MIT | Parakeet speech in about 155 ms on this Mac. A Hex transformation can give the transcript to another program (E4). |
