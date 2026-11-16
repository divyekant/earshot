# Writer brief: mails and notes for the Footnote decision model (E13, package M1)

You are one writer of made-up fit data. Other writers have other owners and other styles. Read `RULE-need.md` and `RULE-when.md` in this folder first: they define the labels.

## Hard rules

1. **Write each mail and each note yourself, one by one.** Do not write a script or a program that makes text from parts, lists or templates. Do not reuse a sentence pattern again and again. This rule is the most important one: an earlier test failed because a generator made the data.
2. **Made-up data only.** No real person, no real company, no real address. Every email address and every web link uses `example.com`, `example.org` or `example.net` (for example `j.okafor@example.org`, `billing@citywater.example.com`, `https://portal.example.net/pay`). Company names are made-up.
3. Write the JSON lines with the Write tool directly. One file part has 25 to 40 lines. Name the parts `items-01.jsonl`, `items-02.jsonl`, ... in your folder. Write the matching labels to `intent-01.tsv`, `intent-02.tsv`, ... Never put a label inside an item.
4. Do not open other writers' folders.

## Format of one item (one JSON object on one line)

```
{"id": "<prefix>-0001", "owner": {"name": "Ana Lim", "address": "ana.lim@example.com"}, "now": "2026-11-03T14:10:00Z", "sender_known": true, "from_name": "Sam Lee", "from_address": "sam.lee@example.org", "to": ["ana.lim@example.com"], "cc": [], "subject": "Signed form", "date": "2026-11-03T09:14:00Z", "list_unsubscribe": false, "precedence": "", "auto_submitted": false, "junk": false, "replied": false, "body": "Hi Ana,\n\nCould you send me the signed form before the 20th?\n\nThanks,\nSam"}
```

- `now` is the time of the read: the same as `date` or up to some hours later. Use dates between 2026-09-01 and 2026-12-20, all in UTC, on all weekdays and at all hours (also late evening and early morning).
- `sender_known`: true if the owner wrote to or replied to this sender before (family, friends, colleagues, a regular client). False for a first contact, a stranger, most organizations.
- A note: `from_name` "", `from_address` "", `to` [], `cc` [], `sender_known` false. `subject` is the first words of the note. `body` is the note text, often several lines.
- `replied` true only for a few mails that the owner already answered. `list_unsubscribe` true for newsletters and marketing (about 1 in 10 of all mails).

## Format of one intent label (TSV, with a header row)

`id	need	kind	sentence	sentence2`

- `need`: `none`, `list` or `now`, by `RULE-need.md` and `RULE-when.md`.
- `kind`: one kind from the list at the end of `RULE-need.md`.
- `sentence` and `sentence2`: for a request, copied character for character from `body` (one sentence each, no line break inside). Empty for `none`.

## The mix in your set

Your set has the counts in your task. Inside it:

- About 1 in 8 mails is a request (`list` or `now`). About 1 in 4 of the requests is `now` by `RULE-when.md`. Most `now` items come from known senders; write 2 or 3 `now` requests from an unknown sender too (for example a neighbor, a courier at the door).
- 1 in 4 of the mails with `none` is hard: a sales mail with a time limit or a command, a survey, a request to another person (the owner in Cc or in a group), a request that is already done or taken back, a polite question with no need for an answer, a trick mail with urgent words, an invitation from a shop, an offer of help, a request only in the quoted old text.
- Real mail is not clean. Write long mails and short ones. Use signatures, legal footers, "Sent from my phone", quoted old text ("On Tue, 3 Nov 2026 at 09:14, Sam Lee wrote:" and lines with ">"), forwarded blocks, lower-case text with no punctuation, typing errors, and mails with two topics where the request is in the middle or at the end. Some requests have no request word (an implied request).
- About 4 in 10 of your notes have a to-do line. The others keep facts, ideas, lists or done things. Notes are never `now`.
- Each owner has their own people, places, work and way of life. Use the owner's details below. Invent the people around them. Vary the senders: family, friends, colleagues, clients, school, doctor, landlord, bank, utilities, shops, clubs, government offices, tradespeople.

## When you finish

Check that each line is valid JSON and that each `sentence` is in its `body`. Reply with the count of items, the count of each `need` value, and the file names. Do not paste the items in your reply.
