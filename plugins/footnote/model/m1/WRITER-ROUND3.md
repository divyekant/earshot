# Round 3 addendum to the writer briefs (E13, package M1, targeted data)

Read this after `WRITER-MAIL.md` or `WRITER-PAIR.md`, and after `WRITER-ROUND2.md`. Where this file differs, this file wins.

Round 3 is targeted. It holds the cases that a small model got wrong. Write the hard cases with care: each one must be a real, natural mail or note, not a puzzle.

## Do not use

These names and their people are reserved: Nadia Brandt, Walter Osei, Tomasz Wilk, Ingrid Halvorsen, Dev Malhotra, Ruth Abernathy, Kenji Morales. Do not use them or their surnames. Do not use Maya Rao. Use new owners: do not reuse an owner name of an earlier round.

## Mail writers: 250 items each (200 mails, 50 notes, 5 owners)

### Mails

About 1 in 4 mails is a request (`list` or `now`). The rest are `none`. Write these kinds:

1. **Another person is asked (about 40 mails, `none`).** The mail asks someone who is not the owner. Mix these forms:
   - The owner is only in Cc, and the ask is for the person in To.
   - The greeting names another person ("Hi Priya,"), and the owner is in To with others.
   - A group mail where each paragraph starts with a name, and no paragraph is for the owner.
   - A mail to the owner that passes on a request for a third person ("Can you tell Sam that he must ...").
   Also write about 10 **close twins** that are requests: the same forms, but one paragraph or one sentence asks the owner by name.
2. **Ads that read like personal mail (about 20 mails, `none`).** A first name as sender, a friendly tone, "I wanted to reach out", a question, a date. But the mail sells something, and it has no `list_unsubscribe` and no `precedence`. Also write about 5 personal mails from a small firm that the owner uses, with a real ask (`list`).
3. **Mass mail with no list header (about 15 mails, `none`).** A club, a school, a building or a firm writes to many people. The mail has no `list_unsubscribe` and no `precedence`. Some have the owner in Bcc only (To is a list address). Some ask "all members" for something that is optional.
4. **Near `now` (about 20 mails).** Write pairs of mails that are almost the same, from known senders. One has a time limit before the next morning list (`now`). The other has a time limit after it, or no time limit (`list`). For example a limit of "tomorrow 8:00" and "tomorrow 14:00", or "the plumber comes in an hour" and "the plumber comes on Friday".
5. **Implied requests (about 10 mails, `list`).** No request word. The owner must act ("The form is attached and the office closes on the 20th.").

### Notes (50)

Write the notes as a person writes for their own eyes: short, often 1 to 3 lines, no greeting, abbreviations, no full sentences. About half have a to-do line (`list`). Examples of forms, do not copy them: "dentist - ring re: crown", "wifi pw: kestrel42", "ideas for Leo bday: kite? lego", "bins out tue", "paid Zara back 20". A note that only records a done thing or a fact is `none`.

## Pair writers

Read `WRITER-PAIR.md` for the format. Use new owners. Each group has the same text A for each candidate B, as before.

### D3 close writers (300 pairs each): minimal triples

For one open item, write 3 texts with almost the same words. Same people, same nouns, about the same length. Only the result changes:

- one text closes the item (label 1): done, arrived, or cancelled ("tuner booked, Thursday at 8");
- one text is the same topic with an event but no result (label 0, `same-topic`): "tuner can do Thursday or Friday, I must ring back";
- one text is a promise, a part, or a question (label 0): "I will book the tuner tomorrow", "booked the tuner, still need the piano mover".

Also write mails from the other party: a confirmation closes; a reminder or a question about the same thing does not. Each text A is one group with its item and 1 to 3 other open items of the owner. About 1 in 3 pairs closes the item. Use the kinds of RULE-pair.md.

### D2 fit writers (200 pairs each): minimal pairs

For one project, write 2 texts that share a key word of the project:

- one fits by sense (label 1, `fit`): "the estate at Marlow has 610 litres" fits the project "Car";
- one has the word in another sense, or belongs to another person's thing (label 0, `other-sense` or `shared-word`): "toy car for Kabir's birthday" does not fit "Car".

Also write the reverse: a text with no word of the project that fits by its records (label 1, `fit-no-word`), and a text with a word of the project that fits another project of the owner (label 0, `other-project`). Each text A is one group with its project and 1 to 3 other projects or items of the owner.

## Label files

As before: `intent-NN.tsv` (mails and notes) or `<task>-NN-intent.tsv` (pairs). The labelers never see them.
