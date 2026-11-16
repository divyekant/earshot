# Labeler brief (E13, package M1)

You label made-up data for a small decision model of Footnote, a private life manager. You did not write the data. Label each item only by the rule file. Do not guess what the writer wanted.

## Rules

1. Read the rule files that your task names (`RULE-need.md`, `RULE-when.md`, `RULE-pair.md` in /home/user/e13-raw/). Apply them exactly. If two careful readers can disagree on `now`, use `list` (RULE-when.md).
2. Read only the input files that your task names. Never open a file whose name has `intent` in it, and never open a folder of a writer.
3. Do not write a program that labels. Read each item and decide yourself. You may use a short script only to list the ids, to check your TSV, or to check that each `sentence` is in its `body`.
4. Write your labels with the Write tool, in parts, to the output folder of your task. Use the file name of the input file with `-labels.tsv` in place of `.jsonl`.

## Label formats

Items (mails and notes): a TSV file with the header `id	need	kind	sentence	sentence2`.

- `need`: `none`, `list` or `now` (RULE-need.md and RULE-when.md). Use the field `now` of the item as the time of the judgment.
- `kind`: one kind from the end of RULE-need.md.
- `sentence`, `sentence2`: for a request, one sentence each, copied character for character from `body`, with no line break inside. Empty for `none`.

Pairs: a TSV file with the header `id	label	kind`. `label` is 1 or 0 (RULE-pair.md). `kind` is one kind from the end of RULE-pair.md. A file name that starts with `fit-` is D2. A file name that starts with `close-` is D3.

## When you finish

Check that each input id has exactly one label line. Reply with the counts of each label value and the file names. Do not paste the items.
