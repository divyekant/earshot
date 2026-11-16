# The decision model of Footnote (experiment E13)

This folder holds the data formats, the bench and the fit code of the decision model. The model makes four decisions (build spec, section 3). It selects. It writes no text (R-FN-4). Each output is a proposal (R-FN-5).

The results are in `docs/experiments/E13-footnote-decision-model.md`.

All data in this folder is made-up. Use `example.com`, `example.org` and `example.net` for each address and each link. `uv run fm check` refuses other domains.

Footnote does not use this model yet. A change of Footnote behavior needs package M5 and the owner's go.

## Commands

Use `uv` (AGENTS.md). Build the Swift program first, because the rules arm and the facts line come from it.

```sh
cd plugins/footnote && swift build
cd model
uv run fm check data/<file>.jsonl.gz          # formats, labels, made-up domains
uv run fm rules-seen                          # the rules of today on the seen phase 3 sets
uv run fm bench data/<file>.jsonl.gz --arm rules --arm pred:<predictions.tsv>
uv run fm sealed S1 <S1.jsonl.gz> --sha256 <S1.sha256> --arm rules   # one time only, counts only
uv run python -m unittest discover -s tests
```

`FOOTNOTE_BIN` sets the path of the Swift program. The default is `../.build/release/footnote`, then `../.build/debug/footnote`.

## Formats

The formats follow the rule files of the design thread: `RULE-need.md`, `RULE-when.md` and `RULE-pair.md` in the project folder `earshot-footnote-model/`.

### Item file (D1 and D4)

JSON lines, plain or gzip. One mail or one note for each line. The fields of the phase 3 fixtures (`phase3-build-spec.md`, section 8.2), and these fields:

| Field | Value |
|---|---|
| `owner` | `{"name": "...", "address": "...@example.com"}` |
| `now` | The time of the read, ISO 8601 in UTC. The same as `date` or later. |
| `sender_known` | Optional, mail only. True if the owner replied to this sender before, or kept a flag of this sender before. If it is not there, the bench uses an earlier mail of the same sender that passed gate 1. |

A note has an empty `from_address` and an empty `to`.

The label file `<name>-labels.tsv` has the columns `id`, `need`, `kind`, `sentence`, `sentence2`.

- `need` is `none`, `list` or `now`. For D1, `list` and `now` are both a request. D4 is the value itself.
- `kind` is for the analysis only. It is not an input.
- `sentence` and `sentence2` are character for character from `body`.

### Pair file (D2 and D3)

JSON lines. One text and one candidate for each line. The file name starts with `fit-` (D2) or `close-` (D3).

```json
{"id": "p0001", "owner": {"name": "Maya Rao", "address": "maya.rao@example.com"},
 "a": {"kind": "capture", "text": "ask Harbour Ceramics for more samples"},
 "b": {"kind": "project", "name": "Kitchen", "records": ["order the paint", "quote from the tiler"]}}
```

- `a.kind` is `capture`, `mail`, `note` or `passage`. `b.kind` is `project` or `item`. `b.records` has 5 or fewer records.
- The pairs with the same text A are one group: the candidates of one text. The arm proposes the candidate with the highest score, or none.

The label file has the columns `id`, `label` (1 or 0) and `kind`.

### Predictions file

TSV. For items: `id`, `need`, `need_score`, `when`, `sentence`, and `facts` from the Swift program. For pairs: `id`, `score`.

### The facts line

Code makes the facts line, not the model (build spec 3.2). The Swift program writes it in the column `facts`:

`owner: Maya Rao | kind: mail | sender: person | to: 1 | limit: today | weekday: Tue`

- `sender` is `person`, `org` (the organization test of the request rule) or `owner` (a note).
- `to` is the count of To and Cc addresses.
- `limit` is the bucket of the earliest time limit that the time reader finds in the text: `today`, `tomorrow`, `this week`, `later` or `none`.

## Sealed sets

The build thread never opens a sealed set. `fm sealed` checks the SHA-256 values, refuses a second run of the same set, prints counts only, and writes a record in `runs/`. Commit the record.
