# E7. Turn recorder, and why room sounds match the wake templates

Status: recorder built. The live session and the cause are open.

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

The live session is not done yet. It needs dk's "go" and a build on the Mac.

### 5.2 Limits of the replay

The record ends with the live turn. So a replay with a shorter end silence shows where the turn would end, but a replay with a longer end silence runs out of kept levels: the end is not known.

## 6. Decisions

- 2026-11-11, dk: the recorder keeps the wake frames and the scores for 7 days, on by default. No audio on disk.
- The gate decision: not yet.
