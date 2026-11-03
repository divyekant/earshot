# E6. Owner voice check on the whole turn, and one profile for each microphone

Date: 2026-11-03. Decision record: [D-11](../DECISIONS.md), change on 2026-11-03 (E6). Requirements: R-ON-1, R-ON-3, R-ON-5, R-MD-1.

## 1. Question

After a change to a USB microphone, the owner voice check rejected the owner. The wake scores fell from 0.73 to 0.37, 0.40, 0.25 and 0.10. The limit is 0.35. Why, and what is the best fix that stays light?

## 2. Answer

- Zero padding of short clips is not the cause. Short audio and the distance to the microphone are.
- The voice of the whole turn (the phrase and the command) gives a surer score than the phrase alone.
- The voice score depends on the microphone. One teach step on each microphone fixes the drop.

The build (D-11, change on 2026-11-03):

1. The voice of the whole turn decides at the end of the turn. The limit goes up with the speech length: 0.35 up to 1 s, then a line up to 0.42 at 2 s.
2. The phrase alone must pass a gate to start the turn. The gate stays at 0.35. The bench found 0.10 best, but the live log shows room sounds that match the phrase every 4 to 6 s (section 6).
3. earshot keeps one voice profile for each microphone.

## 3. Method

The bench is in [`probe/wake-bench`](../../probe/wake-bench) (`voice_bench.py`, `voice_joint.py`, `voice_lengths.py`). It runs in Python on Linux. It is not part of the app.

| Part | What it does |
|---|---|
| Model | WeSpeaker ResNet34-LM in ONNX, the twin of the app's Core ML model (`voxceleb_resnet34_LM.onnx`, CC BY 4.0) |
| Features | A Python port of the app's `MelFeatureExtractor`: 80 mel bands, Hamming window, mean normalization. The clip is zero-padded to the next Core ML length (20, 50, 100, 200, 300, 500, 750, 1000, 1500 or 2000 frames), as in `VoiceModel.embed`. |
| Trim | A port of `SpeechTrim.trim`: the loud part, with 150 ms more at each end |
| Speakers | Mini LibriSpeech `dev-clean-2`: 26 speakers, read speech (CC BY 4.0) |
| Teach step | For each speaker, 5 takes of 0.7 to 1.0 s from one chapter. The profile is the normalized mean embedding. |
| Tests | Up to 24 clips for each speaker from other chapters. A clip is a window that starts on speech and is at least 65 % loud. |
| Far | The same clip with room echo (RT60 about 0.5 s), half the level and pink noise at 20 dB SNR |
| Other voices | Each clip of each speaker against the profiles of the other 25 speakers |

The takes and the tests have different words (text-independent). The owner says the same phrase each time, so the real scores are a little higher. The numbers are conservative.

ONNX CPU time in the Linux container: 35 ms for a 0.8 s clip, 109 ms for a 2.5 s clip. Core ML on the Mac is faster. The app log gives the time of each check.

## 4. Results

### 4.1 Padding and the score rule

Zero padding, repeat padding and no padding (the exact length) gave the same results within about 2 points. Max or top-2 over the 5 takes gave no gain over the mean.

| Clip | Owner passes at 0.35, near | Owner passes at 0.35, far |
|---|---|---|
| Phrase, 0.6 s | 82 % | 18 % |
| Phrase, 0.8 s | 94 % | 34 % |
| Turn, 2.5 s | 100 % | 91 % |

### 4.2 The phrase as a gate, then the whole turn

Phrase clip 0.8 s, turn clip 2.5 s. 419 owner clips and 10,475 other-voice clips in each condition.

| Rule | Owner, near | Owner, far | Other voices, near | Other voices, far |
|---|---|---|---|---|
| Phrase alone at 0.35 (before) | 91 % | 31 % | 0.99 % | 0.32 % |
| Turn alone at 0.42 | 99 % | 78 % | 0.52 % | 0.28 % |
| Gate 0.10, then the turn at 0.42 | 99 % | 73 % | 0.52 % | 0.24 % |
| Gate 0.20, then the turn at 0.42 | 97 % | 63 % | 0.50 % | 0.21 % |

With the gate at 0.10, 31 to 36 % of the other voices that say the phrase reach the speech engine. Their text is dropped at the end of the turn.

### 4.3 Speech length

| Speech | Owner, near, at 0.35 / 0.38 / 0.42 | Owner, far, at 0.35 / 0.38 / 0.42 | Other voices, near, at 0.35 / 0.42 |
|---|---|---|---|
| 0.8 s | 90 / 85 / 79 % | 31 / 23 / 15 % | 0.77 / 0.19 % |
| 1.0 s | 95 / 92 / 85 % | 45 / 36 / 24 % | 1.09 / 0.21 % |
| 1.2 s | 97 / 96 / 92 % | 58 / 49 / 37 % | 1.29 / 0.25 % |
| 1.6 s | 99 / 98 / 96 % | 77 / 70 / 57 % | 1.42 / 0.34 % |
| 2.0 s | 99 / 98 / 96 % | 86 / 78 / 69 % | 1.67 / 0.41 % |

A step from 0.35 to 0.42 at 1.2 s cuts the owner's pass rate at that length (97 % to 92 % near, 58 % to 37 % far). A line from 0.35 at 1 s to 0.42 at 2 s has no such dip. At a fixed limit, other voices pass more often on longer clips, so a longer clip needs the higher limit.

## 5. The build

| Part | Where |
|---|---|
| `VoiceRule`: the gate, 0.35 up to 1 s, a line up to 0.42 at 2 s | `EarshotCore/Wake.swift`. Settings: `voiceGate`, `voiceThreshold`, `turnVoiceThreshold`. |
| The check at the end of a wake turn and of a follow-up turn, from the start of the phrase, on the first 8 s | `EarshotInput/WakeTrigger.swift` |
| `SpeechTrim.condensed`: each quiet part inside the turn cut to 300 ms, as the bench clips have no long pauses | `EarshotWake/SpeechTrim.swift` |
| `TurnVoice` in the log: the score, the speech length, the audio length, the limit and the time of the check | `EarshotApp/CommandPipeline.swift` |
| `VoiceBook`: one profile for each microphone, at most 4, keyed by the Core Audio UID | `EarshotCore/Wake.swift`, `EarshotInput/InputDevice.swift` |

An always-on "send" needs a turn that passed the check (D-12). "send" alone has less than 1 s of speech, so its limit stays 0.35.

## 6. Live data (2026-11-03, HyperX SoloCast, after a new teach step)

| Event | Voice score | Template match score |
|---|---|---|
| 4 wakes by the owner | 0.58 to 0.73 | 0.29 to 0.33 |
| 21 rejected wakes in 3 minutes, one every 4 to 6 s, with no phrase said | 0.17 to 0.29 (median 0.24) | not logged |

- The owner's wakes pass easily on the microphone of the teach step.
- The template matches of the owner sit near the limit 0.33. A stricter template limit would also stop the owner.
- Room sounds or other talk matched the templates often. Only the voice check stopped them. A gate of 0.10 would start a turn, with the start sound, for many of them. So the gate stays at 0.35.
- The rejected-wake log line now has the match score and the worst part, so the next run shows how these matches differ from the owner's.

## 7. Open points

- Find why room sounds match the templates every 4 to 6 s, from the match scores in the next live log. Then the gate can go lower.
- Measure the time of the turn check on the Mac (the log line gives it).
- A teach step on each microphone is one manual step. The status line in Manage > General asks for it when the microphone has no profile.
