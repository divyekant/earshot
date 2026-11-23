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

## Diagnostic X1: hand-written fit data (declared before the first fit)

dk chose "Test hand-written data, in the cloud" (2026-11-16 17:02 UTC). S1 and S3 are open data now (`open/hw1.*`, `open/hw3.*`, the plan in `open/README.md`). X1 is a diagnostic. It gives no pass and changes nothing in Footnote.

Model: ettin-encoder-17m text model, round 3 settings (10 epochs, lr 8e-5, items only), seeds 13, 21 and 34. All arms run behind the full bulk filter and the replied/own gate. Each arm is reported with and without rules gate 2.

| Arm | Fit data | Test | Runs |
|---|---|---|---|
| base | writer data of rounds 1 to 3: the round 3 models `r3-ettin-text-s13/s21/s34`, no new fit | HW1 and HW3 | |
| to-3 | writer data + HW1, weight 4 | HW3 | `x1-to3-w4-sN` |
| to-1 | writer data + HW3, weight 4 | HW1 | `x1-to1-w4-sN` |
| to-3 w1, to-1 w1 (if time allows) | the same, weight 1 | as above | `x1-to3-w1-sN`, `x1-to1-w1-sN` |

- Weight 4 means: each hand-written item is in each epoch 4 times (`stage1 --add-items <file> --add-weight 4`). Mails that the bulk filter holds are not fit data, as for the writer data.
- Thresholds: the round 3 rule on dev1, dev2 and the short-notes dev set only (false flags first, found second). No threshold, seed or setting comes from the test side.
- Median seed: the seed with the median found count on the test side, then the fewest false flags (only for the report, not a selection).
- Output for each arm and seed (`footnote_model.x1`): the D1 mail, notes and D4 lines; false flags and misses by kind; the fewest false flags at 34 or more found over all mail thresholds; a score file (id, arm, seed, request score, `now` score, held).
- Check of the tool: base s21 on HW3 gives the S3 result again (39 found, 32 false; with gate 2 34 found, 20 false).
- Reading rule (design thread): "data closes the gap" if, in both directions, the median seed has 34 or more found and 12 or fewer false flags at the dev threshold, for the model or the model behind gate 2. "Partly" if the false flags fall by half or more against base but stay above 12. "No" for all other results.

## S2 pair arms (declared before the one S2 run, 2026-11-16)

The design thread set a time limit of 19:00 UTC for new pair arms. The student arm is dropped: its teachers saw the same pairs, so it learns the labels. The EmbeddingGemma-input arm has one seed only: the other seeds ran beside the X1 fits on the same 4 cores and were stopped for X1. The mean of 6 models is not an arm (BERT pair s34 did not finish).

| Arm | Model | Thresholds (fit, closes) | Dev D2 project (dev1, dev2) |
|---|---|---|---|
| control | EmbeddingGemma pair features, logistic (`r3-control`) | 0.7236, 0.7925 | 59 of 60, 31 of 33 |
| model | ettin-encoder-17m pair model, round 3 data, 3 epochs, lr 5e-5 (`r3-ettin-pair-s21`) | 0.9073, 0.8086 | 85 of 89, 40 of 41 |
| model+eg | the same, and the 4 EmbeddingGemma pair features go into the pair heads (`r4-ettin-eg-s13`) | 0.9439, 0.9634 | 85 of 89, 44 of 44 |

- `model` is the round 3 pair run that passes D2 project on dev1 and dev2. `model+eg` has one seed, so it has no seed choice.
- The control arm is fit again in the run, with the fit-pair features from the cache of the dev runs. On dev it gives the same D2 project counts as `r3-control`; D2 item changes by 2 proposals (49 to 51) and D3 by 1, because the vectors of llama-server differ a little from run to run.
- The run uses `fm sealed-pairs` on `fit-s2` and `close-s2`, one time each. D2 project is the result line; D2 item is a second line. `runs/S2-fit-predictions.tsv` and `runs/S2-close-predictions.tsv` have the pair id, arm, score and threshold. No text.

## Package L1: check on the owner's recent mail (declared 2026-11-23, before the first read of real mail)

dk chose "Check on my real mail, script only" (2026-11-23 20:58 UTC). Spec: `local-check-spec.md` of the design thread. It is a measurement: no pass and no fail of a mark. The mail text stays on the Mac; the threads get counts only.

Declared configuration: `plugins/footnote/model/l1-config.json`.

- Arms: rules (the shipped rules, `footnote --decide-bench`), model (mean request score of the 3 base Ettin text models of round 3, seeds 13, 21, 34), model+g2 (the model behind rules gate 2; primary). All arms run behind the bulk filter and the replied/own gate on the real header fields.
- Thresholds of the mean score: 0.7 primary, also 0.5 and 0.9. `now`: 0.35, the dev threshold of the mean of 3 (dev1, dev2, short notes). The dev mail threshold of the mean is 0.3 (information only).
- `now` gate: the export cannot see whether the owner wrote to an address before. The counts give `now` before the gate, and after a gate with the rule of `DecideBench` (an earlier mail of the sender in the export passed the filter).
- Model files: the round 3 files of 2026-11-16, stored as 16-bit floats with the tokenizer and encoder config beside them (no download). SHA-256 in the config. Check: with these files, the mean of 3 on HW3 gives the old lines again (0.5: 38/25, g2 33/18; 0.7: 36/11, g2 32/8; 0.9: 35/7, g2 32/5).
- Mail: the inbox of Mail.app, the last 30 days, at most 5,000 mails, newest first. The text is read only for mails that pass the bulk filter. Each mail in the export gets an id of the export (`l1-0001`), not the id of Mail.
- List: up to 12 mails of each group (both, model+g2 only, rules only) and 9 random mails with no flag that pass the filter; random order with seed 20261123; the page does not show the groups.

- Replied group (part A2, added before the first read of real mail): the mails that the bulk filter holds only because the owner replied. They most surely needed the owner. The export reads their text. All arms run on a copy with `replied` set to false; all other gates stay. Counts only, apart from part A (not in the flag counts, the overlap, the `now` lines or the list).
- The check reads the inbox of Mail.app only. Mail that the owner moved out of the inbox in the 30 days is not in it. If the export stops at the cap of 5,000 mails, it says so, and the counts then cover fewer than 30 days.

Commands: `footnote --decide-export <folder>/export.jsonl --days 30`, then `fm local-check score|counts|list|marks|clean --dir <folder>`. A test runs each command on made-up mail and checks that the output has no field of a mail.
