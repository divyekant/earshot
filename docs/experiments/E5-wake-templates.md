# E5. Audio templates against the keyword spotter, for any wake phrase

Date: 2026-11-03. Decision record: [D-11](../DECISIONS.md). Requirements: R-ON-1, R-ON-2, R-ON-3, R-ON-5, R-MD-1.

## 1. Question

The owner can pick any wake phrase: a name, a made-up word or a phrase in another language. Which wake method works for any phrase, stays light on the Mac and needs no extra setup?

## 2. Answer

Audio templates (query by example). earshot keeps the encoder frames of the owner's 5 teach takes and matches the live encoder frames against them with a streaming DTW (dynamic time warping). The method uses no spelling, so it works for any phrase.

On the bench (10 synthetic voices, 8 phrases, 960 test commands):

| Measure | Spotter as shipped | Spotter, reset fixed | Audio templates, limit 0.33 |
|---|---|---|---|
| Hits, near | 49 % | 56 % | 93 % |
| Hits, far field | not measured | 45 % | 95 % |
| False wakes in own talk (8.9 h) | 2 | 1 | 0 |

The templates use the encoder that runs today. They need no new model and no new download. The owner's choice is open: see section 9.

## 3. Why the spotter misses

The spotter (icefall KWS Zipformer, 3.49M parameters) knows 500 English word pieces. earshot spells the phrase in pieces and waits for the model to emit those pieces in that order. So it matches the spelling, not the sound.

1. Rare words and names have no stable spelling. The owner's 5 takes of "hey atlas" gave 5 piece strings (`HE AT LAS`, `HE AT LIST`, `HERE AT LEAST`, `HE AT LEAST`, `HERE KISS`).
2. The learned piece strings from the teach takes are brittle. A new take seldom gives one of them again.
3. The spotter cleared its search every 1.5 s, also in the middle of a phrase. PR #73 fixed this: the reset now waits while a guess is inside the phrase.

## 4. Method

The bench is in [`probe/wake-bench`](../../probe/wake-bench). It runs in Python on Linux. It is not part of the app.

| Part | What it does |
|---|---|
| Spotter | The ONNX twin of the app's Core ML model (sherpa-onnx `kws-zipformer-gigaspeech-3.3M`). A Python port of `StreamingKwsDecoder` and `ContextGraph`: beam 4, 1 trailing blank, spelled pieces (boost 1.0, threshold 0.25), learned pieces (boost 1.5, threshold 0.2). |
| Templates | The encoder frames of the speech part of each teach take (the `SpeechTrim` rule). Streaming subsequence DTW with cosine distance. Steps: diagonal, stay (at most 3 in a row) or skip 1 template frame, with a step cost of 0.05. The score is the mean cost along the path, as the mean of the 2 best templates. |
| Wake rule | Score below the limit, and no lower score in the next 2 frames (80 ms). |
| Worst part | The highest mean cost of 5 frames (200 ms) along the path. Measured as an extra limit. |

The data:

| Set | What it holds |
|---|---|
| Voices | 10 Piper voices: 4 `libritts_r`, 3 `vctk`, 3 `arctic` |
| Phrases | "hey jarvis", "hey atlas", "hey earshot", "okay nova", "hey kairo", "hey zorbix", "hey computer", "arre suno" (Hindi) |
| Teach takes | 5 for each voice and phrase, said alone. Random speed and variation for each take. |
| Test commands | 12 for each voice and phrase: the phrase, then a command. A third are clean, a third have pink noise at 15 dB SNR (signal-to-noise ratio), a third have babble at 10 dB SNR. Half start after the voice's own talk. |
| Far field | 6 more for each voice and phrase: room echo (RT60 0.3 to 0.7 s), half the volume, pink noise at 20 dB SNR. The teach takes stay near. |
| Own talk | About 6 min of each voice that reads text with no phrase. 8.9 h in total. |
| Other talk | LibriSpeech `test-clean` and `test-other`, 10.7 h, 73 speakers. The first 10 chapters of `test-other` are a calibration set only. |
| Sound-alikes | 4 or 5 near phrases for each phrase, 3 takes each |

The spotter port was checked against sherpa-onnx on 72 new test commands. sherpa-onnx woke on 47 and the port on 39. The port is a little strict, but the spotter's misses are real.

## 5. Results per phrase

Hits on the near test commands, 120 for each phrase:

| Phrase | Spotter as shipped | Spotter, reset fixed | Spotter, reset fixed, 10 takes | Templates, limit 0.33 |
|---|---|---|---|---|
| hey jarvis | 40 % | 52 % | 58 % | 95 % |
| hey atlas | 55 % | 53 % | 63 % | 90 % |
| hey earshot | 36 % | 47 % | 57 % | 92 % |
| okay nova | 46 % | 53 % | 56 % | 89 % |
| hey kairo | 61 % | 63 % | 65 % | 97 % |
| hey zorbix | 40 % | 47 % | 53 % | 97 % |
| hey computer | 58 % | 74 % | 80 % | 95 % |
| arre suno | 57 % | 58 % | 61 % | 92 % |
| All | 49 % | 56 % | 62 % | 93 % |

Hits by condition (all phrases):

| Condition | Spotter as shipped | Spotter, reset fixed | Spotter, reset fixed, 10 takes | Templates, limit 0.33 |
|---|---|---|---|---|
| Clean, quiet before | 77 % | 68 % | 71 % | 100 % |
| Clean, talk before | 44 % | 65 % | 71 % | 99 % |
| Pink noise, quiet before | 65 % | 67 % | 78 % | 98 % |
| Pink noise, talk before | 46 % | 69 % | 72 % | 95 % |
| Babble, quiet before | 31 % | 26 % | 31 % | 74 % |
| Babble, talk before | 31 % | 39 % | 48 % | 92 % |

A fusion of the fixed spotter and the templates (wake if either fires) gave no more hits than the templates alone.

## 6. False wakes, sound-alikes and other voices

| Method | Hits, near | Hits, far field | False wakes in own talk (8.9 h) | Wakes in other talk, before the voice check | Sound-alikes that wake it | Other voices that say the phrase, before the voice check |
|---|---|---|---|---|---|---|
| Spotter as shipped | 49 % | not measured | 2 | not measured | 5 % | not measured |
| Spotter, reset fixed, 5 takes | 56 % | 45 % | 1 | 2 in 60 h | 8 % | not measured |
| Spotter, reset fixed, 10 takes | 62 % | not measured | 2 | 2 in 60 h | 10 % | not measured |
| Templates, limit 0.30 | 90 % | 89 % | 0 | 30 in 872 h | 31 % | 80 % |
| Templates, limit 0.33 | 93 % | 95 % | 0 | 51 in 872 h | 39 % | 86 % |
| Templates, limit 0.36 | 96 % | 97 % | 0 | 96 in 872 h | 46 % | 91 % |
| Templates, limit 0.40 | 98 % | 98 % | 2 | 238 in 872 h | 56 % | 95 % |
| Templates, limit 0.33 + worst part 0.5 | 90 % | 94 % | 0 | 28 in 872 h | 28 % | 82 % |

- Other talk: the hours add up over the 80 sets of voice and phrase, because each set listens to the same LibriSpeech audio. The spotter got 0.75 h for each set, because its decoder is slow in Python. For the templates at 0.33, 51 wakes in 872 h is 0.06 an hour. "arre suno" had 36 of the 51.
- Own talk: the lowest template score in 8.9 h of own talk was 0.38. The limit 0.33 keeps a margin of 0.05.
- Sound-alikes: the templates wake on near names after "hey": "hey, Travis" (26 of 30), "hey, Alice" (29 of 30), "hey, Kyle" (29 of 30), "hey, compute it" (30 of 30). They do not wake on sentences that only hold the word: "keep it out of earshot" (1 of 30), "I like bossa nova" (0 of 30), "Jarvis is a common name" (0 of 30).
- Other voices: the templates match the phrase, not the person. The voice check must stop other people. In the D-11 live trial, another voice scored 0.06 against the limit 0.35.

## 7. Delay and cost

- Delay: the median wake came 49 ms after the phrase end for the templates, and 39 ms for the fixed spotter. This is after the encoder frame of the phrase end. Both methods wait for the same encoder chunk, so the method does not change that part.
- CPU: the match of 5 templates took 53 ms of one core for 407 s of audio (Python with numba). That is about 0.13 ms for each second of audio. The encoder runs today. After the owner teaches the phrase, the keyword decoder (beam search and joiner) is no longer needed.
- Memory: 5 templates of about 15 to 25 frames, 320 values each, take less than 100 KB as half floats.

## 8. Proposed design

1. Teach: the owner says the phrase 5 times, as today. earshot keeps the encoder frames of the speech part of each take. It keeps no audio. A take that does not match the other 4 is asked for again.
2. Listen: for each encoder frame, the streaming DTW scores each template. earshot wakes when the score is below 0.33 and the next 2 frames give no lower score.
3. The worst part is logged, but it is not a wake limit by default. If sound-alike wakes occur, a limit of 0.5 on it is the first step.
4. Before the owner teaches the phrase, there are no templates. The spelled spotter wakes earshot, as today.
5. The voice check, the time cut of the phrase (PR #71) and the follow-up turn stay. The follow-up turn uses the same match.
6. A new phrase needs 5 new takes. The voice profile stays.

## 9. Decision

The owner chose A, audio templates, on 2026-11-03. The options were:

| Option | Hits on the bench | What it takes |
|---|---|---|
| A. Audio templates (recommended) | 93 % near, 95 % far | One pull request, the same 5 takes, a live check on the owner's voice |
| B. Keep the fixed spotter (PR #73) | 56 % near, 45 % far | Nothing more |
| C. A small model for each phrase (livekit-wakeword) | Not measured | A training run of minutes for each new phrase, and a training stack on the Mac |

## 10. Limits

- All voices are synthetic. A real person changes more from take to take, so the live hit rate can be lower. A live check on the owner's voice must confirm the numbers.
- The bench ran the ONNX twin of the model on Linux, not Core ML on the Mac. The port of the decoder is a little stricter than sherpa-onnx.
- The far field, the babble and the room echo are synthetic.
- The voice check was not part of the bench. The other-talk and other-voice numbers are before the voice check.
- The limit 0.33 comes from synthetic voices. The live log of near misses must confirm it.
