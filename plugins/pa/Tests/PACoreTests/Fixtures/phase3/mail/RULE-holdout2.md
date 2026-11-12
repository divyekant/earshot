# Second sealed holdout for request flags (PA phase 3)

Written by the design thread on 2026-11-12, after the first holdout failed and before the code of version 2. The design thread wrote it before it saw the failure analysis of the first holdout. All messages are made-up. The owner is "Maya Rao", `maya.rao@example.com`.

- `holdout2.jsonl`: 200 messages, one JSON object for each line. The fields are those of `phase3-build-spec.md`, section 8.2.
- `holdout2-labels.tsv`: `id`, `request` (1 or 0), `kind`, `sentence`, `sentence2`. 20 messages have `request` 1.

Do not open the two data files before the one holdout run. The bench reads them and prints counts.

## The label rule

`request` is 1 if the mail asks the owner to do something or to answer, and it is for the owner: a person wrote it to the owner, or an organization that the owner deals with requires an act (pay, confirm, sign, renew, bring, book, return, collect) by a time.

`request` is 0 for:

- an advertisement, a sales mail or a survey, also with a command or a time limit;
- a newsletter or a notice to a list with no request to the owner by name;
- a receipt, a confirmation or a notice with nothing to do;
- a request to another person, also if the owner is in To or Cc;
- a request that is already done, or that the sender takes back;
- a request of the owner that is only in the quoted old text;
- a thank-you, news, or an offer of help ("let me know if you have questions");
- a mail that the owner replied to already (`replied` is true);
- a mail from the owner's own address.

For `request` 1, `sentence` is the sentence that the owner must see, character for character from `body`. `sentence2` is a second sentence that is also correct, or empty.

`kind` is for the analysis after the run. It is not an input of the PA.

## Limits

The design thread wrote the messages and the labels, and it also wrote the list of features in the build spec. The build thread did not see the messages. The messages are in English. The share of requests (1 in 10) is an estimate, not a measurement of a real inbox.
