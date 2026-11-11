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
| send | `send` | "send" (hold key; in always-on, only "send" alone after typing, D-12, R-NV-5) |
| key | `pressKey`, `undoTyping` | "backspace three times", "new line", "press tab", "undo that" (D-13) |

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

Plain words with no command word are dictation: with the hold key, the pipeline types them into the focused text field (`typeText`), if `ScreenSnapshot.focusedID` names an editable field that is not a password field and the page is not a sign-in, code or payment page. Dictation never presses Return. Always-on mode dictates only after a bare "type": the router sets `RouteResult.awaitsText`, and the next turn that starts within 5 s (in the owner's voice, so it passed the voice check) types its words into the focused field with the same field check. A command word in that turn runs as a command. It is one turn only. The log keeps the word count, not the words. Only a turn whose FIRST sentence is a command runs as a command; a command word later in the text is typed. After earshot typed in always-on mode, a turn that starts within 3 s in the same app, with no command in its first sentence, goes on with the text (one space before it, never Return). Each result plays a short system sound if "Play sounds" is on: one for done, one for sent, one for failed, blocked or not sure. When earshot waits for the owner's words (after "type", or after a typing), it plays no result sound: the note on screen is the cue, and the owner can go on talking at once. A quiet start sound (Tink, volume 0.3) plays the moment earshot starts to listen: on hold-key down, and on the wake phrase (also inside a follow-up turn). It is loaded and warmed up at start, so it plays 20-31 ms after the event. The voice check never hears it: a wake uses the audio of the phrase, before the sound. If earshot's own window is in front, the pipeline first brings back the app that was in front before it; earshot's own window is never a target.

**Spoken keys and "undo that" (I-34, D-13).** The router reads a fixed key list from the words, with a count ("backspace three times", "left arrow twice"). It is text only (under 1 ms) and runs before the screen rules. A key phrase is a command, so dictation never types it. The action module checks the focused element first (`KeyRules`): Backspace and Forward Delete only in a text field, Return only in a text area that is not a message box, and no key on a sign-in, code or payment page. "undo that" removes the last text that earshot typed with Backspace presses, only in the same app and only if the field still ends with that text. A chain can hold a key step after "press" ("type hello, then press tab"). The text of the last typing stays in memory only.

**A chain of commands (I-28).** One sentence can hold up to 10 steps: "click on this, click on that, type this and press send". `CommandRouter.steps` cuts the words at a comma, a sentence end, "and", "then", "and then" or "after that", but only where the next part starts with a step verb and the part before it is a command. After a text verb ("type", "message"), only "then", "and then", "after that" or a sentence end can end the text. A send phrase at the end stays on the text step as "and send", so the send rules of one command hold. The cut is text only (under 1 ms). It adds no verb and no intent. The pipeline routes each step on a new screen read, after the step before it ran and the screen settled (after "open <app>": until the app is in front, at most 2 s). Each step has its own confidence check and action safety check. If a step is not a command, is not sure, is blocked or fails, the chain stops and asks (dk, 2026-11-03): for 10 s, "go on" skips the step and runs the rest, "stop" ends the chain, "yes" runs the best guess of an unsure step, and other words replace the step. In always-on mode, only the owner's voice can answer, and a chain never sends: the owner says "send" on its own (D-12). One sound plays at the end of the chain.

### 3.1 Wake gate (R-ON-1, R-ON-2, R-ON-3, D-11)

| Part | Component | Notes |
|---|---|---|
| Wake phrase | icefall KWS Zipformer (gigaspeech, 3.49M parameters, Apache-2.0), Core ML INT8 (`aufklarer/KWS-Zipformer-3M-CoreML-INT8`), and audio templates (`TemplateMatcher`) | The encoder runs on 320 ms chunks. Vendor time: 5.4 ms for each chunk on Apple silicon. After the owner teaches the phrase, a streaming DTW (dynamic time warping) matches the encoder frames against the owner's takes, and the keyword decoder does not run (E5). It uses no spelling, so any phrase, name or language works. Before the teach step, the spelled spotter listens: the phrase is text, no training. |
| Owner voice check | WeSpeaker ResNet34-LM (VoxCeleb, CC BY 4.0), Core ML (`aufklarer/WeSpeaker-ResNet34-LM-CoreML`) | 256-value embedding. Cosine similarity against the mean of 5 enrolment phrases, from the profile of the microphone in use. The phrase must score 0.35 or more to start a turn (the gate). At the end of the turn, the voice of the whole turn decides: 0.35 up to 1 s of speech, then a line up to 0.42 at 2 s or more (E6). Live trial: owner 0.50 to 0.73, another voice 0.06. |
| End of turn | `SpeechDetector` (energy with a noise floor that adapts) | 550 ms of quiet after the command. After the phrase alone, it waits 2 s for the command. A turn that is expected to hold dictated text (after a bare "type", or after earshot typed in always-on mode) ends after 1200 ms of quiet, so a natural pause does not cut the sentence in two. Two levels, as in Hex: speech starts at 12 dB above the floor (and -50 dBFS); in a turn, only a frame within 4 dB of the floor (or under -70 dBFS) is quiet. A frame between the levels does not count toward the end; after the end silence plus 1 s with no speech frame, the turn ends anyway (noise that changes). The level removes the DC offset of each frame. A command turn is dropped at 15 s (a TV); a dictation turn ends with its text at 60 s. With the optional turn model (Smart Turn v3.2, Core ML, about 17 MB, 3.5 ms for each check), the first pause of 300 ms after 200 ms of speech gets one check on the last 8 s of the turn audio: a probability of 0.5 or more ends the turn at once; a lower one waits up to 2 s of quiet (3 s for dictation). Live test 2026-11-03 gave two limits. After the wake phrase, only speech after the phrase counts (200 ms in total starts the command, and the check needs 200 ms of it), because the model hears "hey atlas" alone as a finished turn. In a dictation turn, the model never ends the turn early: a sentence end is not the end of the text, so only the 1.2 s dictation silence ends it. A new speech frame starts a new pause and a new check. Hex tried the same rule (300 ms, 2 s fallback) and removed it for the size of its ONNX runtime, not for its quality. The turn log note shows each check and how the turn ended (`end quiet`, `end soft`, `end model`, `end grace` or `end limit`, with the quiet time, the end silence and the turn length), so the threshold can be set from the owner's own turns. |

The code is in `app/Sources/EarshotWake`. The spotter and voice code are copied from soniqo/speech-swift at `a57702e` (Apache-2.0, see THIRD_PARTY_NOTICES.md). The models download one time (about 18 MB) at pinned revisions, with a SHA-256 check, into `~/Library/Application Support/earshot/models/`.

How a command flows (`EarshotInput/WakeTrigger.swift`):

1. The wake listener (the spotter encoder, then the templates or the keyword decoder) listens to 16 kHz audio. Between turns, nothing else runs. Speech without the phrase never reaches the speech engine.
2. The listener fires about 0.3 to 0.5 s after the phrase. If a voice is enrolled, the voice model scores the audio of the phrase. A score below the gate (`voiceGate`, 0.35) stops here, and the log gets one line with no text, with the voice score and the match score.
   - With templates, each new encoder frame (40 ms) updates the DTW match of each template. The score of a template is the mean cosine distance along its path: 0 is the same sound, 1 is an unrelated sound. The wake score is the mean of the 2 best template scores. earshot wakes when the score is below 0.33 and the next 2 frames give no lower score. The path can stay on a template frame up to 3 times (slower speech) or skip one frame (faster speech). After a wake, no second wake comes for 1.5 s.
   - The match gives the first and the last frame of the phrase. These take the place of the time stamps of the word pieces, for the voice clip and for the time cut in step 4.
   - The log line of a wake adds the match score and the worst part (the highest mean cost of 200 ms along the path). A match with a worst part of 0.7 or more does not wake earshot (E7). Room sound matched the templates every 4 to 6 s with a worst part of 0.82 to 1.04. The owner's wakes had 0.28 to 0.55. A stopped match does not reset the listener. The near-miss line of the log counts the stopped matches. If sound-alike wakes occur, a limit of 0.5 is the next step (E5).
3. The speech engine starts at the start of the phrase. `MicrophoneFeed` keeps 3 s of audio, and `PrerollControl.setNextPreroll` gives the engine the phrase and every word after it.
4. The turn ends after the command. If a voice is enrolled, the voice model then scores the whole turn, from the start of the phrase to the end (E6, `VoiceRule`):
   - The trigger keeps the first 8 s of the turn for this check. `SpeechTrim.condensed` cuts the quiet ends, and cuts each quiet part inside to 300 ms, so the model scores speech, not the pause after the phrase.
   - The limit depends on the speech that the model scored: 0.35 (`voiceThreshold`) up to 1 s, then a line up to 0.42 (`turnVoiceThreshold`) at 2 s. A longer clip gives a surer score, so a higher limit stops more other voices and still passes the owner.
   - A turn below the limit is dropped: no text is used, no note shows and no sound plays. The log gets one line with the phrase score, the turn score, the speech length, the audio length and the check time.
   - If the check of the turn cannot run (the model failed), the score of the phrase counts, with the limit 0.35.
   - The check runs before the trigger ends the turn, so its time adds to the command path. The log line gives it.
   Then the pipeline removes the phrase, and the router runs as for the hold key.
   - Apple SpeechTranscriber gives the audio time of each word (`.audioTimeRange`). The listener gives the end of the phrase. The pipeline drops the first words that start more than 0.15 s before the phrase end (`WakePhrase.cut`). The start is the sure edge of a word, and the phrase end from the listener tends to be a little late. So the spelling of the phrase does not matter ("Yeah, let's" for "hey atlas").
   - Then the text match (`WakePhrase.strip`) removes what the time cut left, for example the last word of the phrase.
   - With no word times (Parakeet, on-device dictation), the text match alone runs. Apple speech can write the phrase as other words ("Here, at least" for "hey atlas"). So at the start of the text, the match may differ in up to half of the letters of the phrase.
   - Apple speech and dictation get the phrase as a hint (`contextualStrings`).
5. For 5 s after a command, speech in the owner's voice starts a turn with no phrase. The voice is checked at the end of the turn. A follow-up turn that fails the voice check (another voice, or too short) shows no note and plays no sound. The log keeps its voice score and audio length, with no text. A wake phrase in another voice is in the log only, with its score. Change on 2026-11-03: the note "not sure it was your voice" and the failed sound were removed, because other voices, a TV and room sounds set them off too often. While earshot plays a sound (the start sound, a result sound), the always-on detector ignores the audio: the follow-up window starts when the result sound ends, so the sound never becomes a turn or mixes into the next words. When earshot waits for your words (after "type", or after a typing), it plays no result sound, so nothing is muted. The listener keeps on for the first 4 s of that turn, with the same match (live test 2026-11-03: the phrase came about 2 s into a follow-up turn, after other sound, and 2.5 s was too short). If the owner says the phrase again, and its voice passes the gate, the turn becomes a wake turn: the phrase is cut by time, and the voice of the whole turn is checked at the end, as in step 4, from the start of the phrase. Sound before the phrase in that turn does not count for the voice. A phrase in that turn whose voice misses the gate gets a line in the log, as a rejected wake, and the turn stays a follow-up turn. A follow-up turn uses the same limits as a wake turn: "send" alone (under 1 s of speech) needs 0.35, and a long follow-up turn needs up to 0.42. A follow-up turn with 1 s of speech or more that misses the limit also passes if its voice scores 0.45 or more against the voice of the owner's last turn that passed the profile (`VoiceRule.lastTurn`, E6 section 8). The trigger keeps only the embedding of that turn, never its audio. It drops it when the follow-up window closes, at stop, and for a turn that starts more than 30 s of heard audio after it. A pass by the last turn gives no new reference, so a chain of such passes cannot drift from the owner's voice. Live test 2026-11-03: the go-on parts of the owner's dictation, right after earshot typed, scored 0.23 and 0.25 against the profile (which holds the wake phrase only) and were dropped. The log line of each check gives the speech level and the last-turn score.
6. The spelled spotter clears its state every 1.5 s with no wake (the upstream rule). While a guess is inside the phrase, the reset waits up to 1 s more, so a phrase that falls on the reset point can end. The template match has no such reset: each frame can start a new path.
7. The listener counts near misses. The log gets the count every 60 s of audio and at each wake. It has no audio and no text.
   - Spelled spotter: the top guess matched half of the phrase pieces or more, then fell back with no wake, and no wake came in 1 s. The log also gets the best part of the phrase.
   - Templates: a run of frames with a score below 0.41 (the limit + 0.08) that did not wake and did not go below the limit. The log also gets the lowest score of these runs. Use it to tune the limit.

The enrolment (Manage > General > Teach earshot your voice) records 5 phrases. For each take, earshot finds the loud part and runs the encoder on it, with 0.3 s of digital quiet before it and 0.5 s after it. The template is the encoder frames of the loud part, with one more frame at each end. Then earshot scores each take against the templates of the other 4. A take with a lowest score above 0.33 gives no template: it does not sound like the others. At least 3 templates must stay, else the owner must teach earshot again. E5 proposed to ask again for such a take. The build leaves it out instead, so the teach step stays one pass.

earshot keeps the mean voice embedding and the templates (16-bit floats, about 100 KB for 5 takes) in `voice.json`. The profile also learns the owner's free speech: a wake turn that passed the check by 0.05 or more over its limit, with 1.5 s of speech or more, adds its voice embedding (`learnedTurns`, at most 10, the oldest goes first). The check of a whole turn compares with the mean of the 5 phrases and the learned turns. The gate on the phrase alone uses the 5 phrases. Only a wake turn teaches, and only the profile of the microphone in use (or an older profile with no microphone). A new teach step starts with no learned turns (E6, section 8.2: a profile of one phrase passes free speech 73 % to 75 % of the time; with 3 learned turns, 91 % to 94 %). It keeps one profile for each microphone (`VoiceBook`, at most 4), keyed by the Core Audio UID of the default input device at the teach step. Always-on uses the profile of the microphone in use, else the newest profile, and the status line in Manage > General then asks the owner to teach earshot again with that microphone. A new teach step replaces only the profile of its microphone. When the default input device changes, always-on starts again with the right profile. A `voice.json` from before the book holds one profile, and earshot reads it as a book of one. Each teach step adds a line to the activity log: the phrase, the microphone, the take scores and the voice self score. It keeps no audio, and earshot cannot play a template back. The templates count only for the phrase of the enrolment. After a change of the phrase, the spelled spotter listens until the owner teaches earshot the new phrase. The voice embedding counts for any phrase. A profile from before the templates has none: the spelled spotter listens, and the status line in Manage > General asks the owner to teach earshot again. The enrolment no longer learns word pieces for a made-up name.

The turn recorder (E7, [experiments/E7-turn-recorder.md](experiments/E7-turn-recorder.md)) keeps the numbers of each always-on turn and each rejected wake for 7 days, so that a wake or voice problem can run again in a test with no audio. It is on by default, with a switch in Manage > General. Turning it off deletes the kept numbers. Each record is one JSON line in `turns/YYYY-MM-DD.jsonl` (UTC day) in the store folder:
- the sound level of each 20 ms frame, from up to 3 s before the turn to its end, and the noise floor of the detector;
- the wake: the phrase voice score, the gate, the match score, the worst part, and a trace of the match: the match score of each 40 ms encoder frame, from 480 ms before the match to the wake, at most 5 s;
- the wake frames of that trace, as 16-bit floats, the same kind of data as the templates in `voice.json`. earshot cannot play them back. At most 60 records with frames in one hour, and none after 40 MB in one day;
- each answer of the turn model, how the turn ended, the voice check of the turn, and the words and the result as the activity log has them.

The `EarshotReplayTests` target runs the rules again on kept records: `TurnReplay` feeds the kept levels and the kept answers of the turn model to `SpeechDetector`, and gives the same end as the live turn; `TemplateMatcher` runs on the kept frames with the templates of `voice.json`; the gate runs on the kept voice scores. `EARSHOT_TURNS=<turns folder> EARSHOT_VOICE=<voice.json> swift test --filter KeptTurnsReport` prints a summary with numbers only.

Limits:
- The spelled spotter is English only. A made-up name ("hey earshot") also wakes it on sound-alikes ("hey, your shot").
- The templates match the sound, not the person. The voice check must stop other people.
- The templates wake on near names after "hey", for example "hey, Travis" for "hey jarvis" (E5). They do not wake on a sentence that only holds the name.
- The limit 0.33 comes from synthetic voices. The live log of near misses must confirm it.
- The voice check is less sure on short audio. The check of the whole turn helps (E6). The gate on the phrase stays at 0.35, because room sounds matched the phrase every 4 to 6 s in the live run of 2026-11-03 (voice scores 0.17 to 0.29). E6 found a gate of 0.10 best on clean bench audio.
- The voice score and the templates depend on the microphone. After a change of microphone, the owner's wake scores fell from 0.73 to 0.10 to 0.40 (live run, 2026-11-03). The profile for each microphone fixes this after one teach step on the new microphone.
- Intel Macs run Core ML on the CPU. Measure the speed there. The template match adds about 16 ms of CPU time for 10 s of audio (5 templates, release build on Linux, one core). The keyword decoder (beam search and joiner) does not run in template mode.

E5 (2026-11-03, [experiments/E5-wake-templates.md](experiments/E5-wake-templates.md)) measured the spotter against audio templates on 10 synthetic voices and 8 phrases. The spotter matches the spelling of the phrase, so it misses rare words and names: 56 % of test commands woke it with the reset fixed. Audio templates of the owner's 5 takes, matched with DTW (dynamic time warping) on the same encoder frames, woke on 93 %, with no false wake in 8.9 h of own talk. The owner chose this method on 2026-11-03: after the owner teaches the phrase, the template match replaces the keyword decoder. The voice check stays. The template match is built (`TemplateMatcher`, `WakeTemplates`). A live check on the owner's voice must confirm the bench numbers.

### 3.2 Speech to text (R-MD-1, R-MD-5)

| Option | Use when |
|---|---|
| Parakeet 0.6B, the model file of Hex (`parakeet-unified-en-0.6b-Q8_0.gguf`, transcribe.cpp on Metal) | Optional, when the owner chooses "Parakeet" in Settings. It is not the default (live test 2026-11-02, below). earshot reads the file in place, so there is no download. E2: 114 of 126 commands routed correctly, 14.9 % word errors, 34 ms median on short commands. It loads in 14.4 s, so it stays loaded. From transcribe.cpp 0.4.1 the model file is mapped: the footprint after load fell from 887 MB to about 190-205 MB, and macOS can drop the pages under pressure (memory study 2026-11-03, PR #80). English only. Weights CC BY 4.0. |
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
- Edges of a hold-key turn (Hex study, I-1): the engine got 450 ms of audio from before the key press (until 2026-11-11, see the next item), and records 200 ms more real audio after the release, then adds 300 ms of silence. Hex measured 10 of 10 last words kept with 0 to 200 ms after the release, and 7 of 10 with 100 ms less. The 200 ms wait is in `speech.tail`. An always-on turn ends on a pause that the detector heard, so it waits 0 ms (`CaptureControl`).
- Microphone in hold mode (2026-11-11, dk): the microphone is open only while the key is down, like the "Turn off the mic when not dictating" setting of Hex. The feed closes it at the end of each turn (`MicIdle.holdSeconds` = 0), and the key press opens it again. So there is no 450 ms preroll in hold mode. The app opens the microphone before the start sound, so the sound says that the microphone is live. First live reopen: the input was live about 80 ms after the start call. Always-on mode keeps the microphone open, because a wake turn starts up to 3 s before the hit.

Both engines miss the same names, so the router must also match names by sound.

### 3.3 "Is this for me?" (R-ON-2, R-ON-5)

The wake phrase decides (D-11). The first design had a text gate with no wake word (a prefix rule, a follow-up window and a call context). It passed common command words in normal talk, and it had no voice check. D-11 removed it.

The safety rule stays: actions that cannot be undone, such as Send, need the hold key. A false wake can only focus, open or type (`ActionRules.sendBlock`). One narrow exception (D-12): in always-on mode, "send" alone sends if the voice of the whole turn passed the check (E6), earshot typed within 5 s, and the same app is in front. The pipeline checks this and sets `CommandInfo.ownerSendAfterTyping`; `sendBlock` then also checks the message box, the box text, the tier and the page.

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

E7 (2026-11-11, [E7-chat-stages.md](experiments/E7-chat-stages.md)) measured the chat flow in each app and changed the switcher. A switcher list can hold query rows that repeat the typed name, for example Slack "Search for: <name>". earshot groups the list texts into rows, skips query rows, and stops if a query row is above the chat row. If a new field does not take the focus from accessibility (WhatsApp), earshot clicks it. If Return leaves the field open with the name, earshot presses the result row that matches the name. earshot learns the click and the row press for each app.

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

**The answer to a "not sure" note (gap item 5, 2026-11-11).** If one command is not sure, the note shows at most two choices: the best guess first, then the next one. Example: "not sure: two chats match · 1: → Slack · Ravi · 2: → Messages · Ravi". The note stays on screen for 10 s. In that time, the next turn can answer: "yes" or "the first one" runs choice 1, "the second one" runs choice 2, and "no" does nothing. Other words are a new command, and the note goes away. The answer adds no verb and no intent (section 3.0): the words act only on a note that waits, the same as the answer to a chain. In always-on mode, only the owner's checked voice can answer. A choice is never a send and never a press on a risky element, and it runs at the tier `fuzzy`, so the press rules block a risky label (R-NV-5). A click choice finds the same element (role and label) on a new screen read, in the same front app, or it fails with "the screen changed". After "… and send", the answer sends only if the command and the answer both used the hold key. In always-on mode, the owner says "send" on its own (D-12). The choices stay in memory only.

**Habit memory (gap item 6, 2026-11-11).** When the owner picks a choice of a note, earshot keeps the answer in `habits.json` in the store folder, next to `names.json`. An entry holds target keys only: the chosen target and the other targets of the note (an app id and a chat name, or the front app, role and label of an element). It holds no message text. The next time the rules score the same targets the same (within 0.05 of the best score), the router takes the owner's last choice, and the route is sure at the tier `fuzzy`. It changes the order only between those targets. A tie with a target that the note did not show has no habit. A newer answer for the same targets replaces the older one, and the file keeps at most 200 entries. A risky element, a send and plain typing have no key, so a habit never makes a risky press sure (R-NV-5). "No" keeps nothing. The check is a list scan inside the route, well under 1 ms.

**Misheard names (gap item 12, 2026-11-11, [E8](experiments/E8-misheard-names.md)).** Speech can write a label as other words: "cloud" for Claude, "chart" for Chat. When the owner picks a choice of a note, earshot compares the command words with the label of the chosen target and keeps the best pair of 1 to 3 words, by text and by sound, in `heard.json` (heard words, label words, target key; at most 200 entries; no message text). If a later route is not sure or found nothing, the router replaces the heard words with the label words and routes again with the same rules. It keeps the result only if it is sure and goes to the same target key, so the label must be on the screen of the same app, in the names or in the app table at that time (I-15). The route is then sure at the tier `fuzzy`. A send, a risky element and plain typing have no key, and a pair with a risky label is never kept (R-NV-5).

### 3.7 Optional text cleanup

The oMLX server can clean up dictated text: punctuation and filler words. Make it optional, because it adds latency.

Measured on 2026-11-11 ([experiments/text-cleanup-omlx.md](experiments/text-cleanup-omlx.md)): `qwen3.5-0.8b-mlx-4bit` takes 285 ms (median, warm), but it cleaned only 3 of 10 sentences and changed words in 2. earshot has no cleanup setting until a larger general model passes with 0 changed words.

### 3.8 Plugins (R-PL-1 to R-PL-5, D-14)

A plugin is a separate program with a manifest (`docs/PLUGINS.md`). The parts in earshot:

- `EarshotCore/Plugin.swift`: the manifest, the approvals (a SHA-256 of each approved `plugin.json`) and the JSON line messages.
- `EarshotRouter/PluginRouter.swift`: a tier-0 rule. A command that starts with an approved lead becomes the one intent `handOff(pluginID, lead, text)`. The rule refuses a lead that starts with a core command word or an app name, so a core command wins. The words after the lead are text, as after "type".
- `EarshotApp/PluginHost.swift`: starts each approved plugin with posix_spawn, with the responsibility disclaimed, so that the plugin does not get the permissions of earshot. Writes go on a separate queue, so a plugin cannot slow a command.
- `EarshotApp/CommandPipeline+Plugins.swift`: the hand-off after the route. The log keeps the lead and a word count.
- `EarshotUI/PluginsTab.swift`: the list of plugins and the approvals.

The answers show as a note. An alert also goes to the Notification Center. A plugin also gives targets (names with ids). earshot keeps them for a later target source: "open <target>" with the core verb.

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
