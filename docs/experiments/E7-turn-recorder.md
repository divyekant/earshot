# E7. Turn recorder, and why room sounds match the wake templates

Status: recorder built. Worst-part limit 0.7 added. Live session part 1 done; end-of-turn fixes added. Part 2 is open.

Requirements: R-ON-1, R-ON-2, R-ON-3, R-MD-1. Decisions: D-11, D-12.

## 1. Question

In the live runs of 2026-11-03 (HyperX SoloCast), room sounds and a video matched the wake templates about every 4 to 6 s (E6, sections 6 and 8):

| Event | Voice score of the phrase | Template match score |
|---|---|---|
| Owner wakes | 0.41 to 0.74 | 0.15 to 0.33 |
| Rejected wakes (no phrase said) | 0.14 to 0.33, median 0.24 | 0.22 to 0.31, median 0.25 |

The E5 bench gave 0.06 false matches for each hour of other talk. The live rate is about 600 for each hour. Only the voice gate (0.35) stops these matches. E6 found a gate of 0.10 best for the owner on the bench, but a lower gate would start a turn, with the start sound, for many of the room matches.

Questions:
1. Why do room sounds match the templates live, but not on the bench?
2. Can the gate go down toward 0.10 when the false matches stop?

earshot keeps no audio (dk, 2026-11-11: "no audio on disk"). So the evidence must come from numbers that earshot keeps.

## 2. The recorder

For each always-on turn and each rejected wake, earshot keeps one record for 7 days (DESIGN 3.1). The record has the sound levels, the wake scores, a trace of the match (the score of each encoder frame and the encoder frames), the turn checks, the end and the voice check. The `EarshotReplayTests` target runs the rules again on the records.

dk chose on a card on 2026-11-11: keep the wake frames and the scores for 7 days, with the switch on by default (option "Frames + scores, switch on").

## 3. Candidate causes, and the number that tests each

| Candidate | What the records show if it is the cause |
|---|---|
| A. The encoder starts again from zero after each turn and each rejected wake (`PhraseListener.reset`). The teach takes also start from zero, after 0.3 s of digital quiet. So the first frames after a reset look like the start of a template. | Rejected matches start few frames after a reset (`trace.firstFrame + trace.matchStart`), and the owner's wakes do not. |
| B. The templates hold much room sound: the loud part of a take was found too wide, or the room was loud at the teach step. | The kept frames of a rejected match have low cost against the edge frames of the templates. Matches come at room level, not at speech level (`levels` at the match). |
| C. Other speech (the video, a call) matches, as near names did in E5 ("hey, Travis"). | Matches come at speech level, from other voices (phrase voice 0.1 to 0.3), with a low worst part. |
| D. The DTW path can stay on a template frame 3 times and skip frames, so a short sound can stretch over a template. | The path of a rejected match is much shorter or longer than the template. |

## 4. Method

1. Install a build with the recorder on the Mac (thread "Measure Earshot daily use" makes the builds).
2. One live session of 10 min with dk, at the desk and across the room. Cases that did not run before: a far wake, 15 min of talk with no phrase, a long dictation, the send cases (D-12). Type only into dk's own chats.
3. Run `EARSHOT_TURNS=… EARSHOT_VOICE=… swift test --filter KeptTurnsReport` on the Mac. Put the summary (numbers only) in section 5.
4. Test candidates A to D with the numbers in section 3.
5. Change the cause. Then lower `voiceGate` toward 0.10 only if the false matches stop. Record the decision in `docs/DECISIONS.md` (D-11).

## 5. Results

### 5.1 The activity log of 2026-11-03 (read on the Mac on 2026-11-11)

From 00:00 to 07:00 PST, with no owner in the room, the log has 4,731 rejected wakes: about 680 each hour, 11 each minute. Their phrase voice scores: min 0.01, median 0.21, p90 0.24, max 0.34. The gate is 0.35. In the same hours: 7 near misses, 4 wake turns.

- The matches do not need speech: the room was quiet, with no video. This makes candidate C unlikely as the main cause.
- One match about every 5 s, for 7 hours, fits candidate A: each rejected wake resets the encoder (`PhraseListener.reset`), and the frames after a reset can start the next match. So the matches can feed each other.
- A gate of 0.10 would open a turn, with the start sound, for most of these matches. The gate stays at 0.35.

### 5.2 The match numbers of the same night (read by thread A on 2026-11-11)

| Group | Match score | Worst part | Phrase voice |
|---|---|---|---|
| 4,718 rejected wakes, no phrase said | 0.22 to 0.32, median 0.25 | 0.82 to 1.04, median 0.97 | 0.01 to 0.34, median 0.21 |
| The owner's live wakes (2026-11-03, desk) | 0.20 to 0.31 | 0.28 to 0.55 | 0.48 to 0.67 |

Time between two rejected wakes: min 3.69 s, p10 4.91 s, median 5.29 s, p90 5.90 s. 99.7 % fall between 4 and 7 s.

- The match score cannot separate the groups: they overlap from 0.22 to 0.31.
- The worst part separates them with no overlap. A room match fits the mean of the phrase, but one part of 200 ms does not fit at all (cost near 1, an unrelated sound).
- This fits candidate B or D more than C: the matches are not speech.
- The fixed time between matches fits candidate A (the reset chain). A periodic room sound is also possible. These numbers do not rule it out.

The live session is not done yet. It needs dk's "go" and a build on the Mac.

### 5.3 Live session, part 1 (2026-11-11, build af7705c, dk at the Mac)

From 04:29 to 04:32 UTC: 2 wake turns, 2 follow-up turns, 0 rejected wakes, 0 dropped turns. The worst-part limit stopped 24 room matches (21 in the first 83 s, then 3).

| Turn | What the records show |
|---|---|
| Wake 1 (voice 0.42, match 0.13, worst part 0.46) | The detector was muted for 520 ms (the start sound). After the mute, 340 ms of loud frames gave no words: the echo of the start sound. They started the command, and the turn model ended the turn at the first 300 ms pause (P 0.99, 680 ms). The real command was lost. |
| Wake 2 (voice 0.71, match 0.14, worst part 0.28) | About 540 ms of speech after the mute, then the model end (P 0.97, 880 ms). 4 words, not a command. |
| Dictation (follow-up after "type", 82 words) | It ended at the 60 s limit, not at a pause. dk said "send" and the wake phrase again inside it, so the text came late and held them. |

A Python copy of the detector, fed with the kept levels and the kept model answers, gives the same live result (27 checks, no end before 60 s). It shows two causes:

1. In 7 of 18 pauses of 600 ms or more, the model was unsure (P below 0.5). In a dictation turn, an unsure answer made the pause wait 3 s. The real end pauses had P 0.03 and 0.15.
2. In each pause, single frames between the quiet level and the speech level (4 to 12 dB above the floor) set the quiet time back to zero. The longest quiet run in a 3.04 s pause was 1.46 s.

| Rule on the kept dictation | The turn ends at | Before "send" (18.4 s)? |
|---|---|---|
| Live rule (3 s wait, every soft frame resets) | not before 60 s | no |
| Soft runs of 3 frames or more reset; 3 s wait | 27.0 s | no |
| Every soft frame resets; no wait in dictation | 18.3 s | yes, by 0.1 s |
| Soft runs of 3 frames or more reset; no wait in dictation | 17.8 s | yes |
| Soft runs of 3 frames or more reset; 2 s wait | 21.3 s | no |

Changes (PR after #122):

- In a dictation turn, the model answer does not change the pause. The 1.2 s dictation silence ends the turn. The check stays in the log.
- A run of 1 or 2 soft frames does not reset the quiet time (`softBlipFrames` 3).
- The detector ignores 0.3 s more after each sound of earshot (`soundTailSeconds`). In the kept wake 1, this leaves 140 ms of echo, less than the 200 ms that starts a command. So the turn keeps the 2 s grace time for the command.
- A "Listening" note stays on screen for the whole turn, with a level bar (dk, 2026-11-11).

### 5.4 Limits of the replay

The record ends with the live turn. So a replay with a shorter end silence shows where the turn would end, but a replay with a longer end silence runs out of kept levels: the end is not known.

## 6. Decisions

- 2026-11-11, dk: the recorder keeps the wake frames and the scores for 7 days, on by default. No audio on disk.
- 2026-11-11: a template match wakes earshot only if its worst part is below 0.7 (`TemplateMatcher.defaultWorstLimit`). A stopped match does not reset the listener, which also breaks the chain of candidate A. See D-11 in `docs/DECISIONS.md`.
- The gate on the phrase voice stays at 0.35. Lower it toward 0.10 only after a live run with the worst-part limit shows no rejected wakes for 15 min of room sound and talk.
