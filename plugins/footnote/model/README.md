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

### Item file (D1 and D4)

JSON lines, plain or gzip. One mail or one note for each line. The fields of the phase 3 fixtures (`phase3-build-spec.md`, section 8.2), and these fields:

| Field | Value |
|---|---|
| `kind` | `mail` or `note`. A note has an empty `from_address` and no `to`. |
| `owner` | `{"name": "...", "address": "...@example.com"}` |
| `now` | The time of the read, ISO 8601 in UTC. |
| `sender_known` | Mail only. True if the owner replied to this sender before, or kept a flag of this sender before. |

The label file `<name>-labels.tsv` has the columns `id`, `need` (1 or 0), `when` (`none`, `list`, `now`, or empty if not labeled), `category` (for the analysis only, not an input), `sentence` and `sentence2` (character for character from `body`).

### Pair file (D2 and D3)

JSON lines. One text and one candidate for each line.

```json
{"id": "p0001", "task": "fit", "group": "g0001",
 "a": {"kind": "capture", "text": "ring the joiner about the worktop cut-outs"},
 "b": {"kind": "project", "name": "Kitchen", "records": ["order the oak worktop", "plumber on Monday"]}}
```

- `task` is `fit` (D2) or `closes` (D3).
- `group` joins the pairs of one text. A group has up to 5 candidates. The arm proposes the candidate with the highest score, or none.
- `b.records` has up to 5 short records of the project or the open item.

The label file has the columns `id`, `label` (1 or 0) and `category`.

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
