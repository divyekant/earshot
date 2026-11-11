# E8: misheard names (gap item 12, I-15)

Date: 2026-11-11. Base: `develop` 7f89282 (after PR #113 and PR #123).

## 1. Question

Speech to text writes some names and labels as other words. Can the owner's answer to a "not sure" note teach earshot the correct label, with no audio and with no new verb?

## 2. Wrong words in the log

Source: the owner's activity log of 2026-11-02 and 2026-11-03 (230 records, 116 with words, 42 of them failed). The log of 2026-11-04 to 2026-11-10 has almost no use (weekly report of 2026-11-11). The table shows only app names, product words and screen labels. Two misheard person names are left out, because the repository is public.

| Label | Speech wrote | Turns | What earshot did | After this change |
|---|---|---|---|---|
| Claude (app) | "Cloud", "clod" | 8 | 7 opened Claude by sound ("app name by sound"). 1 in Chrome was "not sure": the screen had other labels. | Sound match as before. An answer "yes" for Claude keeps "cloud" → "claude". |
| Chat (screen label) | "chart" | 2 | 1 label match. 1 "no label matches". | An answer keeps "chart" → "chat" for that app. |
| FPL Guru (browser tab) | "SPL Guru", "FPL guru trap" | 5 | 3 correct, 1 "nothing matches", 1 Jev. | An answer keeps "spl guru" → "fpl guru". |
| earshot (in a label) | "ear short" | 1 | Jev picked it. | An answer keeps "reduce ear short" → "reduce earshot". |
| Steer this thread | "steer this thrill" | 1 | Fuzzy label match. | No change. |
| shadcn/ui (tab) | "shad CN/UI" | 1 | "no label matches". | Not covered: "CN/UI" is one piece with two words, and a correction replaces only whole pieces. |
| send | "signed" | 1 | Not a command. | Never corrected. A send and a risky label have no target key (R-NV-5). |
| hnm.com | "Openhnm.com" | 1 | No command word. | Not a name. The web address rule splits glued words (R-NV-7). |

Result: about 20 turns had a misheard target. The sound code (E2) already corrects most app names. Screen labels and tab titles have no such help.

## 3. Design

- When the owner picks a choice of a note, earshot compares the command words with the label of the chosen target. It takes the best pair of 1 to 3 heard words and label words, by text and by sound (`CommandRouter.heardWords`). The score must be 0.5 or more. Command words, fillers and stop words at the two ends do not count, so no message text goes into the pair.
- earshot keeps the pair in `heard.json` in the store folder: the heard words, the label words and the target key of the habit memory (`TieHabits.key`). At most 200 entries.
- The router uses a pair only if the rules are not sure or found nothing. It replaces the heard words with the label words and routes again with the same rules. The result counts only if it is sure and goes to the same target key. So the label must be on the screen of the same app, in the names or in the app table at that time (I-15). The route is then sure at the tier `fuzzy`.
- A send, typing with no target and a risky element have no key. A pair with a risky label is never kept. So a correction never makes a send or a risky press sure (R-NV-5).

## 4. Tests

`app/Tests/EarshotRouterTests/HeardFixTests.swift` holds the test set of I-15 with made-up names: the heard words, the label and the pair. It also tests the same-target rule, the screen-label rule in the same app, the send rule, the store limit and the route time. `app/Tests/EarshotAppTests/ChoiceTests.swift` tests the answer, the pair and the next route.

## 5. Latency

The check runs only for a route that is not sure, and it is a list scan. The route time with 200 entries is in the pull request.

## 6. Open

- A correction inside one piece ("CN/UI").
- A view of the pairs in Manage, to remove a wrong pair. Today, remove `heard.json` to clear all pairs.
