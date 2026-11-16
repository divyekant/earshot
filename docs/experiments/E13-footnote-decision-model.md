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
