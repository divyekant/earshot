# Writer brief: pairs for the Footnote decision model (E13, package M1)

You are one writer of made-up fit data. Read `RULE-pair.md` in this folder first: it defines the pairs and the labels.

## Hard rules

1. **Write each text yourself, one by one.** Do not write a script or a program that makes text from parts, lists or templates. Do not reuse a sentence pattern again and again. An earlier test failed because a generator made the data.
2. **Made-up data only.** No real person or company. Each address and link uses `example.com`, `example.org` or `example.net`.
3. Write the JSON lines with the Write tool directly. One file part has 30 to 60 lines. Name the parts `<task>-01.jsonl`, `<task>-02.jsonl`, ... (task `fit` or `close`, as your task says). Write the matching labels to `<task>-01-intent.tsv`, ... with a header row `id	label	kind`. Never put a label inside a pair.
4. Do not open other writers' folders.

## Format of one pair (one JSON object on one line)

```
{"id": "<prefix>-0001", "owner": {"name": "Ana Lim", "address": "ana.lim@example.com"}, "a": {"kind": "capture", "text": "ring the joiner about the worktop cut-outs"}, "b": {"kind": "project", "name": "Kitchen", "records": ["order the oak worktop", "plumber booked for Monday 23rd", "tiles from Harbour Ceramics, sample 4"]}}
```

- `a.kind`: `capture` (a short line the owner said or typed), `mail` (subject, a line break `\n`, then the body), `note`, or `passage` (a few sentences from a kept web page or document). Use all four. Mails and passages can be long and messy, with signatures and quoted text.
- One text A has 1 to 4 candidates B: write one line for each candidate, each with its own id and the same `a` exactly. These lines are one group.
- For a project: `b.records` has 1 to 5 short records that the owner put into the project (their own words: to-dos, facts, names, amounts). For an item (`b.kind` `item`): `b.name` is the words of the open item and `b.records` is empty.

## The mix

- Use the owners in your task. Give each owner 6 to 10 projects and 10 to 20 open items. Keep them the same through your set, so the same project comes back with other texts. Records can change a little over time, as a real project grows.
- The labels and the hard cases are in your task.
- Vary the length and the style: short captures with no capital letters, typing errors, voice-typed text with no punctuation, long mails.

## When you finish

Check that each line is valid JSON. Reply with the count of pairs, the count of each label, the count of groups, and the file names. Do not paste the pairs in your reply.
