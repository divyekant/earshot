# E7. Chat flow stages in Slack, Messages, WhatsApp and Mail

Date: 2026-11-11. Requirements: R-SP-1, R-NV-2, R-NV-3, R-NV-6, R-MT-1, R-NV-5.

## 1. Question

"Slack Ravi, running late" must reach the focused message box in about 1 s or less from the end of speech (R-SP-1), in Slack, Messages, WhatsApp and Mail (R-NV-6). The activity log of 2026-11-02 and 2026-11-03 showed 5 of 11 chat turns OK, with a median of 1,417 ms from the end of speech. Which stage is slow, and which stage fails?

## 2. Answer

| App | Before (develop 4db3621) | After (this change) |
|---|---|---|
| Slack | 0 of 5. Return opened a search page, not the chat. | 5 of 5. Median 437 ms to the focused box. |
| Messages | 5 of 5. Median 691 ms. | 5 of 5. Median 682 ms. |
| WhatsApp | 0 of 5. The new-chat field did not take the focus. | 5 of 5. Median 1,475 ms. |
| Mail | No chat row in the catalogue. | No change. See section 6. |

The times are from the start of the action to the focused box. They do not include the final transcript and the router. E0 measured the final transcript at 23 to 101 ms, and the router takes less than 15 ms. So, from the end of speech: Slack about 0.5 s and Messages about 0.8 s meet R-SP-1. WhatsApp, about 1.6 s, does not. Its remaining time is in the app (section 5).

## 3. Method

The bench is `ChatStageBench` in `app/Tests/EarshotActionsTests`. It runs only on the owner's Mac, with `EARSHOT_LIVE_CHAT=1`, from a process that has the Accessibility permission. CI skips it.

- It reads the owner's catalogue (`apps.json`), names (`names.json`) and learned focus methods. It writes the learned methods to a temporary folder, not to the store.
- For each chat app, it opens the owner's own chat 5 times. Before each run, it puts Finder in front, as a voice command does.
- It types no message text and presses no Send. It stops at the focused message box.
- It prints the stages of `ActionOutcome`. The printed lines have no chat names.

The second test, `testSwitcherRows`, prints the rows of a switcher list after the name. It types the name only into a switcher field, never into a message box, and it presses no Return. It is for a failure study only.

WhatsApp shows the owner's own chat as "<short name> (You)", not with the owner's full name. The WhatsApp runs used that short name (`EARSHOT_BENCH_TARGET`). See section 7.

## 4. What failed, and the fixes

### 4.1 Slack: Return ran a search

Slack (2026) changed Command-K into one search list. For a typed name, the list shows these rows:

1. The chat row, for example "<name>, Direct Message", if Slack finds one.
2. "Search for: <name>", with the part "Show results for:" and the name as its own text.
3. "Ask Slackbot about <name>".

The old result check looked for any new text that matches the name. The name in row 2 matched, so earshot pressed Return while the search row was on top, or before the chat row showed. Slack then opened a search page, and no message box was there.

The fix (`ActionRules.switcherResult`, `ActionRules.rows`):

- earshot groups the result texts into rows by their frames. A section label whose frame covers two or more rows (Slack "Suggestions") does not join the rows.
- A row with a text that starts with "search for", "show results", "search in", "search all" or "ask " is a query row. It is not a result.
- The result is a chat only if the first row that matches the name is not below a query row. If a query row is above it, earshot presses Escape and stops: "the first result is a search, not the chat". It does not open a search page.

### 4.2 WhatsApp: the field took no focus, and Return did not open the result

WhatsApp Command-N shows the new-chat field in about 430 ms. The field is new, so the scan finds it. But WhatsApp ignores `AXFocused`, and it reports its focus as a group.

The fixes:

- If the field is still without focus at the next scan, earshot clicks it one time, at a point where the field is the top element (`safePoint`). earshot learns "click" for the app and clicks at the first find the next time.
- After Return, earshot reads the field, not the focus. If the field is still on screen with the name after 250 ms, Return did not open the chat. earshot then presses the top new result row that matches the name (`ActionRules.pickResultRow`). It never presses a query row or a row with a risky word (`SafetyPolicy.isRisky`). earshot learns "row" for the app and presses the row at once the next time, with no Return.

A chat row opens a chat. It sends nothing (R-NV-5).

## 5. Stage table

Median of 5 runs, in ms from the start of the action. "chat" is the mark after the chat opened. "focus" is the focused message box.

| Stage | Slack before | Slack after | Messages before | Messages after | WhatsApp after |
|---|---|---|---|---|---|
| front | 19 | 18 | 24 | 23 | 37 |
| key | 40 | 37 | 26 | 86 | 158 |
| switcher | 173 | 123 | 279 | 302 | 654 |
| name | 261 | 181 | 327 | 355 | 710 |
| result | 450 (false hit) | 342 | 560 | 553 | 749 |
| chat | 451 | 436 | 563 | 620 | 792 |
| focus | no box | 437 | 691 | 682 | 1,450 |
| OK | 0 of 5 | 5 of 5 | 5 of 5 | 5 of 5 | 5 of 5 |

Notes:

- Slack after: "chat" now includes the wait until the switcher field closes after Return (about 90 ms). The box then has the focus at once.
- Messages: the first accessibility read after Command-N waits about 200 ms while Messages opens the "To:" field. Messages is busy, so a faster poll does not help.
- WhatsApp: the new-chat field needs about 430 ms to show, and the chat needs about 650 ms to load after the row press. The box search reads 72 nodes, 3 times. The time is in the app, not in earshot.
- The first run of each app is slower (Messages 1,579 ms before, 806 ms after), because the app is not warm.

## 6. Mail

The catalogue on the owner's Mac has Mail as an app with no chat row (`isChat` false), so "Mail <name>" opens Mail only. The generic switcher could treat Mail as a chat app with Command-N and the "To:" field. What it can and cannot do:

- Can: Command-N opens a new message window with the focus in "To:". The name gives an address list. Return takes the top address. The message body is a wide box in the lower part of the window, so the composer rule finds it.
- Cannot, or not safely:
  - Each command opens a new draft window. A failed command leaves a draft.
  - The chat check reads the name from the window title or the text above the box. A new mail has the title "New Message", and the address token is not a chat header.
  - "Mail <name>" means a new mail, not the last thread with that person. The owner may expect a reply.
  - Mail has a subject field between "To:" and the body.

No design change is made for Mail in this change. The owner must choose if "Mail <name>, text" starts a new mail.

## 7. Open points

- WhatsApp own chat. The owner's own chat in WhatsApp has the short name of the owner's contact card and "(You)". `NameIndex` adds the full owner name when the sidebar has no "(you)" row, so "WhatsApp me" types a name that WhatsApp does not find. A fix can read the "(You)" row of the new-chat list once, at name warm-up.
- Slack own chat in a large workspace. In one Slack workspace of the owner, the list for the owner's full name shows no chat row in the first 1.5 s, only search rows and files. earshot now stops safely there.
- A failed WhatsApp command can leave the new-chat panel open. Escape does not close it. The next Command-N then finds no new field.
