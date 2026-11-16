# E13: a decision model for Footnote

Status: open. Package M0 is done. Packages M1 and M2 are next.

Source: the build spec `/mnt/project-files/earshot-footnote-model/build-spec.md` in the project folder (2026-11-16). Requirements: R-FN-4, R-FN-5, R-FN-7, R-FN-8. Code and formats: `plugins/footnote/model/`.

## Question

Can a very small model of our own make the four decisions of Footnote better than the rules of today? The model selects. It writes no text.

| ID | Decision | Output |
|---|---|---|
| D1 | Does this mail or note need the owner? | `need`, and a score for each sentence |
| D2 | Is this text part of this project or open item? | `fit` |
| D3 | Does this text close this open item? | `closes` |
| D4 | When must the owner hear about it? | `when`: `now`, `list` or `none` |

## End result and marks

A model file of 20 MB or less (target 10 MB) inside Footnote, 10 ms or less for one text on the Mac CPU. The marks for each decision are in the build spec, section 6. For a set of another size than S1, the bench uses the same shares (34 of 40 is 0.85).

## M0: frame and the rules of today

Date: 2026-11-16.

- `plugins/footnote/model/`: a `uv` project with the formats, the checks, the marks and the sealed run (`uv run fm`).
- `footnote --decide-bench <items.jsonl> --out <predictions.tsv>`: the rules arm. It writes one prediction for each item and the facts line. It prints counts only.
- The Footnote package builds on Linux again. Two macOS calls (`autoreleasepool`, `malloc_zone_pressure_relief`) had no Linux form.

The rules arm on the seen sets (`uv run fm rules-seen`). The request rule was fitted on build-a and design-a, so the numbers on those two sets are optimistic. Holdout 2 is the only set that the rule did not see before its run.

| Set | Mails | Requests | Flags | Found | False | Sentence correct | D1 mail mark |
|---|---|---|---|---|---|---|---|
| build-a | 300 | 45 | 46 | 45 | 1 | 45 | pass (seen in the fit) |
| design-a | 200 | 20 | 20 | 19 | 1 | 19 | pass (seen in the fit) |
| holdout2 | 200 | 20 | 14 | 13 | 1 | 13 | fail: 17 needed |

These are the numbers of E11. D4 of today has no judgment: each flag goes to the morning list, and no item gives `now`. D2 of today needs the search model. Its arm comes in M2. D3 has no rule today.

### Deviations from the build spec

- The marks are computed in Python (`fm bench`), not in the Swift program. The Swift program gives the predictions and the facts line. Reason: the model arms run in Python until package M4, and one mark code serves all arms.
- `limit` in the facts line is the earliest time limit in the text, not the limit of the selected sentence. Reason: the facts line goes into the model before a sentence is selected.
- The D2 and D3 marks count proposals for each text: the pairs with the same text A are one group. The label formats are those of the rule files of the design thread.

## Code gates before the model

The code gates are part of the system, not of the model. The model does not learn them.

- If `replied` is true, the result is `none`. The model does not run.
- If the sender address is the owner address, the result is `none`. The model does not run.

The bench applies the same gates to every arm (rules, control, models), so that the arms compare (`code_gate` in `formats.py`, `apply_code_gate` in `bench.py`). On the round 1 data, the gates hold 58 fit items and 17 dev items. No gated item has a request label.

## M1 round 2 and the stage 1 text arms (fixed before the S1 run)

Round 2 added 1,994 items, 986 D2 pairs and 1,192 D3 pairs from 9 new writers. Each set had a second reader. Writer and reader agree on 0.976 to 1.0 of the labels. A third reader on 1 in 10 agrees on 199 of 201 items, 98 of 100 D2 pairs and 119 of 120 D3 pairs. The fit data keeps only the labels where writer and reader agree.

dev1 is the round 1 dev set and does not change. dev2 has the new owners of round 2. The thresholds come from dev1 and dev2 together. All arms use the code gates.

Arms for the one run on S1 (2026-11-16, before the run):

| Arm | Model | Seed | Thresholds (mail, note, now) |
|---|---|---|---|
| rules | Swift rules of today | none | rules |
| control | logistic models on EmbeddingGemma vectors | none | 0.62, 0.78, 0.56 |
| Ettin text | ettin-encoder-17m, 10 epochs, lr 8e-5, items only | 13 | 0.15, 0.98, 0.31 |
| BERT text | bert_uncased_L-4_H-256_A-4, 12 epochs, lr 1e-4, items only | 21 | 0.07, 0.14, 0.41 |

The seed of each model arm is the seed with the median dev2 result. If two seeds are equal, the first seed is used.

Dev results (3 seeds, D1 mail found / false):

| Arm | dev1 (43 requests, 334 mails) | dev2 (64 requests, 334 mails) |
|---|---|---|
| Ettin text | 38/4, 39/2, 38/4 | 53/2, 54/4, 53/4 |
| BERT text | 38/10, 37/8, 37/8 | 57/6, 53/7, 52/6 |
| control | 27/6 | 28/6 |

The dev2 found mark is 55. Ettin misses it by 1 or 2. The loop-end rule applies: no more tuning for dev2.

## S1 result (one run, 2026-11-16)

D1 fails on S1 for every arm. The build spec stop rule applied, and dk chose "Targeted data, then a new test". Full counts: `plugins/footnote/model/runs/S1.md`.

| Arm | D1 mail found (mark 34 of 40) | False flags (mark 10 of 400) | Sentence (mark 28) |
|---|---|---|---|
| rules | 28 | 16 | 25 |
| control | 23 | 25 | 15 |
| Ettin text s13 | 35 | 22 (11 to 18 with the bulk filter) | 32 |
| BERT text s21 | 37 | 35 | 30 |

Harness fault: the model and control arms did not apply the full bulk filter in this run. See the note in `runs/S1.md`. From round 3, every arm runs behind the full bulk filter, and the facts line has `owner in` (to, cc or none) and `greets` (owner, other, group or none). A second model arm runs behind gate 2 of the rules (`model+g2:`).

## M1 round 3 and the S3 arms (fixed before the S3 run)

Round 3 is targeted data from 8 new writers. It adds 963 items (agreement 0.956 to 0.972), 399 D2 pairs and 600 D3 pairs (agreement 0.995 to 1.0). Round 3 is fit data only. The short notes of one owner of each mail writer are a dev set for the note threshold (`short-notes-dev3`, 39 notes).

Gates for every arm, in this order:

1. The full Swift bulk filter (`code_gate`). The run stops if it does not hold 186 of the 400 S3 mails (`--expect-held 186`).
2. The `now` gate: `now` only from a known sender.
3. Arm `model+g2` only: gate 2 of the rules ("greets another" or "not for owner").

Arms for the one run on S3 (2026-11-16, before the run):

| Arm | Model | Seed | Thresholds (mail, note, now) |
|---|---|---|---|
| rules | Swift rules of today | none | rules |
| control | logistic models on EmbeddingGemma vectors (`r3-control`) | none | 0.61, 0.82, 0.56 |
| model | ettin-encoder-17m, 10 epochs, lr 8e-5, items only, rounds 1 to 3 (`r3-ettin-text-s21`) | 21 | 0.02, 0.16, 0.38 |
| model+g2 | the same model behind gate 2 | 21 | 0.02, 0.16, 0.38 |

Dev results with the bulk filter (D1 mail found / false; requests that pass the filter):

| Arm | dev1 (42 requests, 334 mails) | dev2 (58 requests, 334 mails) | short notes dev3 (20 to-dos) |
|---|---|---|---|
| Ettin text s13 | 36/7 | 48/1 | 18 found, 2 false |
| Ettin text s21 | 37/7 | 52/4 | 19 found, 1 false |
| Ettin text s34 | 37/8 | 52/6 | 20 found, 1 false |
| control | 25/6 | 27/8 | 2 found, 0 false |

Seed rule as before: the median dev2 found count is 52 (s21 and s34). The first of the two, s21, is used. D4 passes on dev for all three seeds.

## S3 result (one run, 2026-11-16)

D1 fails on S3 for every arm. The filter held 186 of 400 mails, as declared. Full counts: `plugins/footnote/model/runs/S3.md`.

| Arm | D1 mail found (mark 34 of 40) | False flags (mark 10 of 400) | Sentence (mark 28) |
|---|---|---|---|
| rules | 24 | 20 | 22 |
| control | 30 | 29 | 19 |
| model (Ettin text s21) | 39 | 32 | 34 |
| model+g2 | 34 | 20 | 31 |

Notes: the model finds 43 of 50 to-dos with 9 false flags (false share 0.17, mark 0.10). D4: the model finds 7 of 11 `now` items from known senders (mark 8) and gives `now` correctly 7 of 7.

Stage 1 fails. The stage 1 report (`/mnt/project-files/earshot-footnote-model/stage1-report.md`) has the failed marks, the findings, and the size and CPU time of the text model (67 MB in float32, 29.7 ms for 256 tokens on 1 cloud CPU thread).
