# Decisions

This log records the options that the owner and Claude examined on 2026-11-01, and the decision for each one.

## D-1. A dictation app alone is not enough

| Option | Result | Reason |
|---|---|---|
| macOS Dictation | Rejected | Only dictation. Less accurate. No routing. |
| Handy (MIT) | Not enough | Local and light, but only dictation. |
| VoiceInk (GPLv3) | Not enough | Local Whisper, AI cleanup through oMLX, per-app styles ("Power Mode"). Types only into the focused field. |
| Wispr Flow | In use now; not enough | Cloud processing. About 1.4 GB of memory. The free plan has a weekly word limit. Its "voice to action" feature is only on the roadmap (Master Plan post, 2026-03-03) and has not shipped. Its MCP server is read-only. |

**Decision:** Keep Wispr Flow or VoiceInk for plain dictation. Build earshot for routing, focus and clicks.

**Change on 2026-11-11 (the owner's choice, after the gap evaluation of v0.3.0):** earshot is the dictation tool. This replaces the decision above. earshot already types plain words with the hold key, and after "type" in always-on mode (DESIGN 3.0). To replace a dictation app, earshot adds:
- spoken keys: "backspace three times", "new line", "tab" (D-13);
- "undo that": earshot removes the last text that it typed (D-13);
- optional text cleanup on the local oMLX server, off by default (DESIGN 3.7, D-5).

Dictation with no "type" in always-on mode (I-26): the owner chose "no" on 2026-11-11. Always-on types only after a bare "type", or as go-on text within 3 s after a typing. Reason: a false wake could type speech that was not for earshot.

## D-2. Do not use large-model agents for each step

| Option | Result | Reason |
|---|---|---|
| Claude (desktop or computer use) | Rejected | 1–5 s for each model call. Navigation needs 3–4 steps, so 5–20 s in total. |
| OpenClaw, Hermes Agent | Rejected | Same agent loop and same latency. These agents work mainly through tools and APIs, not fast navigation of the user interface. |
| ChatGPT Voice desktop, VoiceOS, mrmr | Rejected | Cloud, not open source, or invite-only. |

**Decision:** Use a "System 1" design. Small fast models choose from a limited set of actions. No model plans steps.

## D-3. Do not use fixed scripts for each app

A Hammerspoon script with one recipe for each app was proposed first. The owner rejected it, because each new app and each app update needs script changes.

**Decision:** Use one data table with one row for each app, and generic accessibility logic (DESIGN.md, section 5).

## D-4. Siri AI is not the base

Siri AI shipped as a public beta in macOS 27 on 2026-09-14. It needs macOS 27, and this Mac runs macOS 26.3.1. A third-party app works only if it adopts the App Intents messaging schema. WhatsApp support on the Mac is not confirmed. Siri AI is also not open and does not do generic clicks.

**Decision:** Do not depend on Siri AI. Check it again when the owner upgrades to macOS 27.

## D-5. Small models, all local

The owner sees the screen and gives exact commands. The system matches the command to a small set of choices. It does not need to reason.

**Decision:** Use models of 0.6B parameters or fewer for speech and routing. Use no model for label matching (string similarity). Use the oMLX server only for optional text cleanup.

## D-6. Native Swift app (proposed)

The best components for the Mac are Swift libraries:
- AXorcist and Peekaboo for accessibility
- FluidAudio and speech-swift for VAD, speech to text, turn detection and speaker embeddings
- Apple Vision for OCR

A native menu-bar app also uses less memory than Electron.

**Decision:** Build earshot as a Swift menu-bar app. A Hammerspoon or Python prototype is acceptable for Phase 0 measurements only. Change this decision if Phase 0 shows a better option.

## D-7. Do not use computer-use agents or Cua Driver

The owner asked about "CUA" on 2026-11-02. The facts below come from the trycua/cua README and the cua.ai documentation. Later the same day, E4 ran Cua Driver on this Mac (see the end of this section).

| Option | Result | Reason |
|---|---|---|
| Computer-use agent (CUA) loop, for example Claude computer use or the OpenAI CUA model | Rejected | This is the agent loop of D-2. A large model reads a screenshot and selects one action for each step. Each step takes 1–5 s. |
| trycua/cua: Lume, Cua Spaces, SDKs, Cua Bench | Rejected | These parts run agents in virtual machines, or they test agents. earshot must operate the real desktop of the owner. |
| Cua Driver (MIT, pre-release) | Rejected | See the list below. |
| CUA-S1 models (trycua) | Not needed now | These are small "System 1" models. The first model only makes decisions about form fields. It does not select a chat or a text box. |

Cua Driver is the only part of trycua/cua that operates the real Mac. These are the reasons not to use it:

- It uses the same Accessibility API as earshot, through one more process. It does not make earshot faster. The project publishes no latency numbers.
- By default, it does not raise the window or change the frontmost app. Its foreground mode does one action and then restores the previous app. earshot must leave the owner in the chat, with the cursor in the text box (R-NV-3).
- Its main interface is an MCP server (R-MD-6). It has no Swift bindings.
- Its setup needs an install script, a background service, and two permissions: Accessibility and Screen Recording.
- If a model controls it, the model can press Return. Return sends the message in Slack, WhatsApp and Messages (R-NV-5).

**Decision:** Keep the direct Accessibility approach (DESIGN.md, section 3.5). The E0 probe uses it, and it reached the Slack text box in a median of 466 ms (docs/experiments/E0-viability.md). Cua Driver reads the accessibility state again after each action to make sure that the change occurred. E0 already does a similar check: it types text only when the chat name on the screen is correct. Keep this check in the final design.

**E4 (2026-11-02):** E4 ran Cua Driver 0.38 on this Mac, with the same glue program as a direct AX executor ([experiments/E4-hex-cua.md](experiments/E4-hex-cua.md)). A Cua click took 1.8 to 2.2 s. The AX click took 318 to 333 ms. A bare Cua call took 15 ms, so the cost is in the action tools. One Cua click reported success, but the page did not change. Cua shows no keyboard focus, so a chat step cannot prove where its text goes (R-NV-5). The decision stands.

## D-8. Do not use Clicky, HeyClicky or LocalClicky

The owner asked about "Clicky" on 2026-11-02. Three products use this name. The facts below come from their READMEs and websites. Nobody ran them on this Mac.

| Option | Result | Reason |
|---|---|---|
| Clicky (farzaa/clicky, MIT, Swift) | Rejected | It is an AI tutor. It sends a screenshot and the spoken question to Claude, speaks the answer, and points a cursor at a user-interface element. It does not click, type or open a chat. |
| HeyClicky (heyclicky.com) | Rejected | Closed, hosted successor of Clicky. Its "agent" mode does tasks with a cloud model. The site does not list its actions or its latency. |
| LocalClicky (dikshantrajput/LocalClicky, MIT) | Rejected | Local, but it is an agent loop. A model of 8B parameters calls tools for up to 5 rounds. A vision model finds a box on a screenshot and clicks it. |

These are the reasons:

- Clicky and HeyClicky send audio and screenshots to cloud services: AssemblyAI, Claude and ElevenLabs (R-MD-1).
- All three use a large model for each request or each step. This is the loop of D-2 (R-SP-2).
- Clicky does not do the earshot task. It does not open the chat or put the cursor in the text box (R-NV-3).
- Setup is large. Clicky needs an Xcode build, a Cloudflare Worker and three API keys. LocalClicky needs Ollama, Whisper.cpp, a Python environment and model downloads. AGENTS.md says to use oMLX, not Ollama.
- If a model can act, it can press Return. Return sends the message in Slack, WhatsApp and Messages (R-NV-5).
- The open Clicky repository stopped on 2026-04-27. New work is private.

**Decision:** Keep the direct Accessibility approach of E0 (DESIGN.md, section 3.5). Generic Accessibility logic plus one data row for each app is general and fast. A model that reads the screen for each command is general but slow.

**Idea to keep:** Clicky moves a cursor to the element that it talks about. earshot can use a similar pointer as feedback before a voice click (R-FB-1, R-CL-1).

## D-9. Jev as an opt-in tier 2

Date: 2026-11-02.

The E1 and E2 router tests compared the rules on the Mac, Jev alone, and the rules with Jev only when the rules are unsure.

| Test | Rules on the Mac | Jev alone | Rules, then Jev if unsure |
|---|---|---|---|
| E1 chats, 42 commands | 40 | 39 | 42 |
| E2 web pages, 45 commands (offline) | 42 | 44 | 45 |

Jev added about 100 ms when it was called (warm connection). Jev alone made wrong choices that the rules did not make, for example a press on "Packages" for "click pricing plans".

**Decision:** The router uses Jev only as an opt-in tier 2.
- It is off by default. The owner switches it on in the app.
- It sends text only: the command words and the short list of candidate labels. Audio never leaves the Mac.
- It runs only when the rules are unsure.
- It has a budget of 1 s. After the budget, the rules answer wins.
- The screenshot fallback for clicks (D-10) is a separate setting. "Ask Jev" never turns it on.

## D-10. Jev sees the screen: an opt-in click fallback

Date: 2026-11-02.

The owner asked for an option: take a screenshot, send it to Jev with the command, and get back the point to click. On 2026-11-02 the owner chose "Yes, front window, set-of-marks" on the question "Allow Jev to get a screenshot of the front window as a click fallback?". The choice was: "Off by default, hold key only, never sign-in/code/payment pages. Jev picks a drawn number; raw x,y only via a coarse grid."

The TypeSafe API takes images (an `assets` map and the header `TypeSafe-Danger-Zone-Images: true`) and has a `box` question that gives a box on the image. So earshot uses the box in place of a coarse grid. E3 measured it (see [E3](experiments/E3-screenshot-fallback.md)).

**Decision:** earshot can ask Jev with one picture when a click finds no target.
- It is a separate setting, "Jev sees the screen". It is off by default. It needs the Jev key and the Screen Recording permission.
- It runs only for a hold-key command, never in always-on mode (R-ON-5), and only after the rules found no sure target.
- It sends the command words and one JPEG of the front window. It never sends a picture of a sign-in, code or payment page, or of a page that can be a hidden tab. It never sends audio. earshot never saves the picture.
- The picture has the "show numbers" numbers drawn on it (set-of-marks). Risky elements get no number. Jev picks a number. Only if no number fits does earshot use Jev's box.
- Before a click, earshot checks the element under the point: it must belong to the front app and have a label, and no risky label or risky text may be under the point. The click path then runs with the tier "jev", so `SafetyPolicy.mayPress` blocks every risky label. earshot never sends (R-NV-5).
- It has a budget of 1.5 s. After the budget, earshot does nothing.

**How it differs from D-2.** D-2 rejected agents that take a screenshot, ask a large model, act, and repeat, in 3 to 4 steps of 1 to 5 s each. This fallback asks once for each command, only after the rules fail, and never loops (R-SP-2). The rules still decide most commands in a few ms.

## D-11. Wake phrase and owner voice for always-on

Date: 2026-11-02.

The owner asked: always-on mode must start only on a wake phrase or a name, as "Hey Siri" does, and react only to the owner's voice. Use a light version of an open project that solves this. This replaces "no wake word" in R-ON-1 and the "is this for me?" text gate in always-on mode. The full search is in [research/wake-phrase-options.md](research/wake-phrase-options.md).

| Option | Result | Reason |
|---|---|---|
| Keyword spotter + speaker check, files copied from soniqo/speech-swift (Apache-2.0) | Chosen | The phrase is text, so no training. Core ML, macOS 14, Intel Macs. About 18 MB of models. |
| The speech-swift package | Rejected | It needs macOS 15, and its speaker code pulls in MLX. That breaks the macOS 14 and Intel build. |
| k2-fsa/sherpa-onnx | Rejected | Same models, but a C++ static framework, ONNX Runtime and a fetch script. |
| livekit/livekit-wakeword, openWakeWord | Not now | Fewer false wakes, but each phrase needs a trained model. The openWakeWord ready models are non-commercial. Keep livekit-wakeword as the upgrade if the spotter fires too often. |
| Picovoice Porcupine + Eagle | Rejected | Closed engine and an online access key (R-MD-4). |
| A text match on the transcript (Swabble) | Rejected | Speech to text runs on all speech, and there is no voice check. |

Tests on 10 synthetic voices (Piper text to speech, 800 phrases of other talk, the ONNX version of the same spotter):

| Phrase | Owner phrases that woke it | Other talk that woke it | Delay after the phrase |
|---|---|---|---|
| "hey earshot", spelled | 7 of 168 | 0 of 600 | 476 ms |
| "hey earshot", learned from 5 owner phrases | 64 of 80 | 53 of 800, all sound-alikes ("hey, your shot") | 470 ms |
| "hey jarvis", spelled | 69 of 80 | 0 of 800 | 325 ms |

The spotter does not know the made-up word "earshot". It hears "your shot" or "here shut".

Live trial on the owner's Mac (2026-11-02, phrase "hey atlas", Apple speech, 15 records):

| Measure | Result |
|---|---|
| Model download and load | 7 s for the download. No errors. |
| Owner wakes | 8. Voice scores 0.50 to 0.73 (median 0.63). Enrolment self score 0.75. |
| Another voice (`say` through the speaker) | 1 wake, voice score 0.06, rejected. 4 other `say` voices did not wake the spotter. |
| Commands that worked | 238 to 541 ms in total. |
| Commands that failed | 7 began with a misheard form of the phrase ("Here, at least", "He at least"). The strict text match kept it, so the router found no command. The looser match at the start of the text removes it in 5 of the 7. |

Second live test on the owner's Mac (2026-11-02, develop `e6f0ba8`, phrase "hey atlas", Apple speech):

| Measure | Result |
|---|---|
| Wake turns | 4 of 4 fired in the owner's voice (0.53 to 0.66). |
| Follow-up turns | 3 began with "Yeah, let's": the owner said the phrase again in the 5 s window. The spotter did not listen in a turn, so no wake came. |
| Text match | The edit distance from "yeahlets" to "heyatlas" is 5. The loose limit is 4, so the text kept it. Result: one 2.6 s Jev and app search, and one lost "type". |

**Decision:**
- The keyword spotter (icefall KWS Zipformer, 3.49M parameters) listens for the phrase. The phrase is a setting. The default is "hey jarvis", because real words work best.
- If the spelled phrase does not fire on the owner's enrolment phrases (a made-up name), the spotter also listens for the word pieces that it heard in them.
- At each wake, the voice model (WeSpeaker ResNet34-LM) compares the voice of the phrase with the mean of the 5 enrolment phrases. The threshold is 0.35 (cosine). The live trial gave 0.50 to 0.73 for the owner and 0.06 for another voice. Tune it from the log.
- Speech without the phrase never reaches the speech engine. So earshot keeps no text of talk that is not for it. A wake in another voice, and a follow-up turn in another voice, are logged with the voice score and no text.
- The speech engine starts at the phrase (a longer preroll), and the pipeline removes the phrase from the text. Speech to text can write a known phrase as other words, so the first words of the text may differ from the phrase in up to half of its letters.
- For 5 s after a command, the owner's voice can give the next command with no phrase. The voice is checked at the end of that turn.
- Remove the phrase by time, not by spelling, where the engine gives word times (Apple SpeechTranscriber). Keep the text match as the fallback. The spotter stays on in the first 2.5 s of a follow-up turn, so a phrase said again there becomes a wake. Log near misses as a count and the best part of the phrase only.
- The safety rules do not change. Always-on never presses Send or a risky button (R-ON-5, `ActionRules.sendBlock`). The hold key stays (R-ON-4).
- The models download one time from Hugging Face, at pinned revisions, with a SHA-256 check. No audio leaves the Mac (R-MD-1).

**Change on 2026-11-03 (E5, [experiments/E5-wake-templates.md](experiments/E5-wake-templates.md)):** the owner wants any phrase, name or language to work. The spelled spotter matches the spelling, so it misses rare words and names.

| Method on the E5 bench (10 synthetic voices, 8 phrases) | Test commands that woke it, near | Far | False wakes in 8.9 h of own talk |
|---|---|---|---|
| Spelled spotter, reset fixed | 56 % | 45 % | 0 |
| Audio templates of the 5 takes, streaming DTW, limit 0.33 | 93 % | 95 % | 0 |

- After the owner teaches the phrase, audio templates find it: the spotter encoder runs, and a streaming DTW matches its frames against the owner's 5 takes. The keyword decoder does not run.
- A take that does not match the other takes gives no template. At least 3 must stay.
- The enrolment no longer learns word pieces for a made-up name.
- Before the teach step, and for a profile from before the templates, the spelled spotter listens, as above.
- The voice check, the time cut of the phrase and the follow-up turn do not change.
- livekit-wakeword stays "Not now": it needs a training run for each phrase.
- A live check on the owner's voice must confirm the bench numbers and the limit 0.33.

**Change on 2026-11-03 (E6, [experiments/E6-voice-check.md](experiments/E6-voice-check.md)):** after a change to a USB microphone, the owner's wake scores fell from 0.73 to 0.10 to 0.40, and the voice check rejected the owner. E6 measured the voice model on 26 real speakers (Mini LibriSpeech). Zero padding of short clips is not the cause: zero, repeat and no padding are the same within about 2 points. Short audio and distance are.

| Rule (E6 bench, phrase 0.8 s, turn 2.5 s) | Owner, near | Owner, far | Other voices, near | Other voices, far |
|---|---|---|---|---|
| Phrase alone, 0.35 (before) | 91 % | 31 % | 0.99 % | 0.32 % |
| Phrase gate 0.10, then the whole turn at 0.42 | 99 % | 73 % | 0.52 % | 0.24 % |

The owner chose "Turn check and one print per mic" on a card.

- At the end of an always-on turn, the voice of the whole turn decides. The limit goes up with the speech length: 0.35 up to 1 s, then a line up to 0.42 at 2 s. A step at one length cut the owner's pass rate there (E6 length sweep). Follow-up turns use the same rule, so "send" alone still needs 0.35 (D-12).
- The gate on the phrase alone stays at 0.35, not the 0.10 of the bench. In the live run of 2026-11-03, room sounds matched the phrase templates every 4 to 6 s for 2 minutes, with voice scores of 0.17 to 0.29. A gate of 0.10 would start a turn, with the start sound, for many of them. The owner's wakes on the same microphone scored 0.58 to 0.73. The gate is a setting (`voiceGate`). Lower it only after the false template matches stop.
- earshot keeps one voice profile for each microphone (at most 4), keyed by the Core Audio UID of the default input device. Always-on uses the profile of the microphone in use, and starts again when the default input device changes.
- A dropped turn shows no note and plays no sound (PR #92). The log keeps the scores.
- A follow-up turn with 1 s of speech or more that misses the limit also passes at 0.45 or more against the voice of the owner's last turn that passed the profile (E6, section 8). Live test 2026-11-03: two go-on parts of the owner's dictation scored 0.23 and 0.25 against the profile and were dropped. On the bench, at 2.8 s far from the microphone, the owner passes 95 % of the time (was 66 %), and other voices 0.78 % (was 0.25 %). "send" alone stays on the profile (D-12).
- The profile learns the owner's free speech from wake turns that passed well (E6, section 8.2). The 5 takes hold the wake phrase only, and follow-up turns in the owner's voice scored 0.16 to 0.28 in the live retest of 2026-11-03. Only a wake turn teaches, at 0.05 or more over its limit and with 1.5 s of speech or more. At most 10 turns. Embeddings only, no audio.
- Rejected: max or top-2 over the 5 takes instead of the mean (no gain on the bench); repeat padding (no gain).

**Change on 2026-11-11 (E7, [experiments/E7-turn-recorder.md](experiments/E7-turn-recorder.md)):** a worst-part limit stops the room matches.

| Night log of 2026-11-03, 7 h, no owner in the room | Match score | Worst part | Phrase voice |
|---|---|---|---|
| 4,718 rejected wakes (no phrase said) | 0.22 to 0.32, median 0.25 | 0.82 to 1.04, median 0.97 | 0.01 to 0.34, median 0.21 |
| The owner's live wakes (E5 first live run) | 0.20 to 0.31 | 0.28 to 0.55 | 0.48 to 0.67 |

- A template match wakes earshot only if its worst part is below 0.7 (`TemplateMatcher.defaultWorstLimit`). The two groups do not overlap, and 0.7 is 0.15 above the owner's highest value.
- A stopped match does not reset the listener. The near-miss line of the log counts the stopped matches.
- The gate on the phrase voice stays at 0.35. The highest rejected voice score in the night log was 0.34, so a lower gate would open turns for room sound if the worst-part limit fails. Lower the gate toward 0.10 only after a live run on the new build shows no rejected wakes for 15 minutes of room sound and talk, and the owner's wakes still pass.
- Not done: a worst-part limit of 0.5 (E5: it cut near hits from 93 % to 90 %). It stays the next step for sound-alike wakes.

## D-12. "send" alone after typing, in always-on mode

Date: 2026-11-03.

The owner chose this on a card: in always-on mode, earshot never sent, so a dictated message needed the hold key to send. The wake phrase and the owner voice check (D-11) make a false send much less likely than before.

| Option | Result | Reason |
|---|---|---|
| Send stays hold-key only | Rejected by the owner | It breaks a hands-free message. |
| "send" alone after typing, in the owner's checked voice | Chosen | Narrow: it needs a recent typing, the same app and a checked voice. |
| Any "send" in always-on | Rejected | A false wake or another voice could send. |

**Decision:**
- In always-on mode, "send" alone (the router's send phrases, after lead fillers) sends only if all are true:
  - the voice of the turn was checked as the owner's: the voice of the whole turn passed the limit for its length (E6, change to D-11 on 2026-11-03). Before E6, the voice of the phrase alone counted for a wake turn;
  - earshot typed into a box within 5 s (typeText, typeInto, armed typing, or openChat with text);
  - the front app is the app of the typing.
- Each typing allows one send.
- `ActionRules.sendBlock` keeps all its other checks: the tier, the message box, a box with text, and no sign-in, code or payment page.
- Anything else in always-on mode stays blocked: "send needs the hold key".
- A trailing "and send" after text is never typed. With the hold key, earshot types and then sends. In always-on mode, it types only, and the note says to say "send" on its own.
- If no voice is enrolled, no voice check runs, so always-on never sends.

## D-13. A "key" verb for spoken keys

Date: 2026-11-11. Idea I-34. Rule 2 of DESIGN 3.0: a new verb needs a reason here.

The owner chose earshot as the dictation tool (change to D-1). Dictation needs keys that are not text: Backspace, Return, Tab, Escape and the arrows. No current verb can do this:

| Option | Result | Reason |
|---|---|---|
| "type" with a key name | Rejected | "type" types its words as text. `Keys.type` removes control characters, so it can never press Return (R-NV-5). A key name in the text would type the name. |
| "press" on a screen target | Rejected | A key is not a target on the screen or in the menus. The menus have no item for Backspace or Return. |
| A menu item, for example Edit > Undo, for "undo that" | Rejected | The step of the menu Undo differs between apps. It can undo more than earshot typed, or undo the owner's own typing. |
| One verb "key" with a fixed key list, and "undo that" as Backspace presses | Chosen | One generic verb. The list names no app and no feature. |

**Decision:**
- One intent `pressKey(key, times)`. The key list is fixed: Backspace ("delete"), Forward Delete, Return ("new line", "enter"), Tab, Escape and the four arrows. 1 to 20 presses.
- A word that is also a command or a menu title ("delete", "enter", "return", "tab", "up") is a key only after "press", "hit" or "tap", or with a count. A bare "undo" stays the app's menu item Edit > Undo.
- Return keeps the send rule. earshot never presses it in a message box: only "send" may press Return there (R-NV-5, `SafetyPolicy.mayPressReturn`). It presses Return only in a text area, not in a one-line field, because Return there can submit a form. A box that is short, wide and low in the window, or whose label says message, reply, compose, write or send, is a message box. In always-on mode, "new line" needs the owner's checked voice, and a chain never presses Return. The always-on send rule (D-12) does not change.
- Backspace and Forward Delete only in a text field: outside a field, they can delete a selected item, for example a mail.
- No key on a sign-in, code or payment page.
- One intent `undoTyping`. "undo that", "scratch that" or "delete that" removes the last text that earshot typed, with one Backspace for each character. It runs only if all are true: the same app is in front, the typing was within 2 minutes, the focused field still ends with that text, and the cursor is at its end with no selection. Else it does nothing and says why. One undo for each typing. After an undo, "send" alone has no typing to follow.
- earshot keeps the text of the last typing in memory only, for "undo that". The log and the note show only its length.
## D-14. Plugins are separate programs

Date: 2026-11-11. Status: accepted, experimental until a second plugin exists. Requirements: R-PL-1 to R-PL-5. Contract: `docs/PLUGINS.md`.

The owner asked for a structure so that other people can add to earshot, and for the personal assistant as the first addition (idea I-35).

Decision: a plugin is a separate local program with a manifest. earshot gives it the text after its lead words, and gets back answers and targets. One intent, `handOff`, serves all plugins.

Rejected:

| Option | Why it was rejected |
|---|---|
| Plugin code inside the earshot app | The code gets the Accessibility and Microphone permissions of earshot. A fault stops earshot. |
| The personal assistant as fixed code in earshot | Each user gets it. No structure for other additions. |
| A plugin that sends commands back to earshot | A plugin could then click, type or send. An answer is text only (R-PL-3). |
| A child process with the default spawn | macOS gives a child the privacy permissions of the app that started it. earshot disclaims the responsibility of each plugin. |

Rules for dictation:

- With the hold key and no "type", a sentence that starts with a lead goes to the plugin, not into the focused text box.
- After a bare "type", the next turn is dictation (R-NV-4). A lead in it is text. The owner gave an explicit command to type.

## D-15. A command line in the app program, with a socket file

Date: 2026-11-11. Status: accepted. Requirements: R-CT-1 to R-CT-4. Commands: `docs/CONTROL.md`.

The owner asked for a way to change settings without the window, so that agents can test and change earshot with no clicks.

Decision: the app program is also the command line. When the first word is a control word, it runs one command and stops. The command line edits `settings.json` itself, then tells the running app through a Unix socket file in the store folder. The app reads the file again.

Rejected:

| Option | Why it was rejected |
|---|---|
| A local HTTP server | It opens a network port. Any local program, and a web page through the browser, can call a port. |
| A separate command-line program | A second build product. The command line must be the same signed program for the peer check. |
| Distributed notifications only | The app cannot know the sender, and the command line gets no answer. |
| Plugin approval from the command line | The owner approves each plugin (R-PL-4). An agent must not approve its own plugin. |

Limits:

- `run --actions` asks two things: the program that starts the command line has the Accessibility permission, and the socket peer has the code signature of earshot. A program of the same user that can change the earshot files can still do much. The command line does not protect against such a program.

