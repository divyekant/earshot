# Mail and note fixtures for request flags (PA phase 3, E11)

All messages are made-up. The owner is "Maya Rao", `maya.rao@example.com`.

| File | Messages | Request 1 | Written by | Use |
|---|---|---|---|---|
| `train.jsonl`, `train-labels.tsv` | 400 | 80 | build thread, `scripts/make-mail-fixtures.py` | Fit the formula. |
| `dev.jsonl`, `dev-labels.tsv` | 200 | 20 | build thread, same script | Select the variant and the threshold. |
| `notes-train.jsonl`, `notes-train-labels.tsv` | 60 | 30 | build thread, same script | Notes with and without a to-do line. |
| `notes-dev.jsonl`, `notes-dev-labels.tsv` | 30 | 15 | build thread, same script | Notes, development. |
| `holdout.jsonl`, `holdout-labels.tsv` | 200 | 20 | design thread | Sealed holdout. Run one time. |

- The format of a message is in `phase3-build-spec.md`, section 8.2. A note has an empty `from_address`.
- The label rule is in `RULE.md`, section "The label rule". It applies to all files here.
- The holdout files came into the repository before the code of the request rule. The build thread did not open them. `holdout.sha256` has their SHA-256 values.
- Do not tune a number on the holdout.
