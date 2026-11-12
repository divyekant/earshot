# E11: request flags for the PA plugin

Status: closed. Version 1 and version 2 failed the found mark on a sealed holdout. On 2026-11-12 04:34 UTC, the owner chose to use version 2 as a list: `rules.request` is `list` by default, and the guide says that the PA finds about half of the requests.

Source: the PA phase 3 build spec, section 8, and the flags v2 spec (`/mnt/project-files/earshot-pa/phase3-build-spec.md` and `phase3-flags-v2-spec.md` in the project folder). Requirements: R-PA-4, R-PA-5.

## Question

Can fixed rules and a small score find the mails and notes that ask the owner to do something? A flag is one quiet line in the list: `Request · <sender> · <one sentence of the mail>`. The PA selects the sentence. It writes no text.

## Marks

| Data | Pass |
|---|---|
| Sealed holdout (200 messages, 20 requests) | 16 or more of the 20 found. 5 or fewer false flags. For 13 or more of the found ones, the shown sentence is a labeled sentence. |
| The owner's 100 research items, on the Mac, numbers only | 0.84 or more of the items with a to-do get a flag. 0.10 or less of all flags are on items with no to-do. |

## Version 1

- The data: `train.jsonl` and `dev.jsonl`, made by one generator with fixed templates.
- The steps: the bulk filter, then 12 sentence features, then variants A to D (A: points by hand; B: two logistic models; C: model vectors; D: B and C together).
- Development: each variant found 20 of 20, with 0 to 2 false flags. The tie rule selected A, at 4.
- Holdout, one run (2026-11-12 03:54 UTC): 31 flags, 12 of 20 found, 19 false, 12 correct sentences. **Fail.**
- Cause: the generator made the development data too easy. 13 of the 19 false flags came from organizations (ads and surveys). 5 came from requests to another person. The features looked at the words of a request, not at who the request is for and who writes.

## Version 2

- New data: `build-a.jsonl`, 300 messages written one by one (45 requests), with no generator. The first holdout became the second data set, `design-a.jsonl`. Version 1 data is not in the fit.
- Gate 2, for the owner: a sentence counts only if a greeting or a name at its start names the owner. With no name, the owner must be in To with 3 addresses or fewer. Quoted and forwarded blocks are cut.
- Gate 3, who writes: an organization needs a duty: an act, a time limit, and a thing of the owner. A mail from an organization with 2 or more sales signs and no thing of the owner gets no flag.
- New features: no request word ("any chance", "tell me by"), done or taken back, offer or small talk, and first mail of an organization.
- All word lists are in `plugins/pa/Sources/PACore/Mail/RequestWords.swift`. They were set with build-a and design-a only.
- Selection across writers: fit on one set, measure on the other, both ways. A at 4 found 19 of 20 on design-a and 45 of 45 on build-a, with 1 false flag in each direction. The lists were set on these sets, so these numbers are optimistic.
- One deviation from the spec: a list mail that names the owner does not pass. The engine reads no text of a list mail, because a text read can block Mail for up to 2.2 s.

### Results of version 2

| Data | Flags | Found | False |
|---|---|---|---|
| Sealed holdout 2, one run | 14 | 13 of 20 | 1 |
| Owner's items, all 100 | 23 | 23 of 53 (0.43) | 0 of 47 |
| Owner's items, 69 mails | 19 | 19 of 37 (0.51) | 0 of 32 |
| Owner's items, 31 notes | 4 | 4 of 16 (0.25) | 0 of 15 |

- On holdout 2, 13 of the 13 found had a correct sentence. The go mark failed on "found" (16 needed).
- Of the 7 misses on holdout 2, gates stopped 3 (2 duty mails with no sign of a thing of the owner, 1 list mail). The score stopped 4 (requests with no word of the lists, a duty as a statement, a lower-case command with no time).
- The owner's items have 53 items with a to-do and 47 with none. An earlier count of 67 counted to-dos, not items.

## Conclusion

Version 2 is precise: 1 false flag of 37 flags on new data. It finds only about half of the requests. The owner chose version 2 as a list, from 4 options (version 2 as a list, no request flags, flags only for mail from persons, a test of one small model of 0.8B or less).

## The learning (spec 8.8)

- Variant A is a linear formula. The hand points are the base weights. Minus the threshold is the base offset.
- After 50 answers with 10 or more of each kind, a logistic fit starts at the base weights, with a penalty for the distance from them.
- A guard fits without the last 20 answers and compares on them. The PA keeps the new weights only if they get more of those 20 answers correct than the base weights.
- The gates do not learn.
- A test with two made-up owners (`FlagLearningTests`). Each owner answered the 66 flags that the base weights show on build-a and design-a. Only 66 flags exist, not 80. The test counts on holdout 2 (now seen) and on `dev.jsonl`.

| Made-up owner | False flags on holdout 2, before | After | Requests found on dev, before | After |
|---|---|---|---|---|
| Drops all flags of organizations | 5 of 14 | 2 of 10 | 14 | 13 |
| Keeps only flags with a time limit | 4 of 14 | 0 of 10 | 14 | 14 |

- Pass: fewer false flags for the two owners, and found requests on dev fall by 2 or fewer. Both pass.
- A separate rule: after 3 dropped flags from one sender address and no kept flag, the PA makes no more flags from it (setting `flagsMuted`).

## How to run the bench

```
earshot-pa --flags-bench plugins/pa/Tests/PACoreTests/Fixtures/phase3/mail            # two-way table and selection
earshot-pa --flags-bench <folder> --analyze design-a --threshold 4                     # a table by kind (seen data only)
earshot-pa --flags-bench <folder> --items <set> --owner-names a,b --owner-addresses x  # counts only
```
