# Ideas and experiments

This file is the owner's to-do list of ideas for earshot. Add each new idea here, with the date. Move an idea to "Done" when a pull request ships it, with the PR number. An idea is not a requirement: `docs/REQUIREMENTS.md` stays the source of truth.

Status words:

- **Open**: nobody works on it.
- **In progress**: a thread works on it. The line names the thread or the PR.
- **Done**: a merged pull request ships it.
- **Later**: the owner chose to wait.

## Open and in progress

| # | Date | Idea | Status | Notes |
|---|---|---|---|---|
| 1 | 2026-11-03 | Study the Hex source: how it records and ends dictation, handles pauses and long text, plays its start sound, sets up Parakeet, inserts text, and does hands-free use. Then apply what fits to earshot. | In progress | Another thread does the study. |
| 2 | 2026-11-03 | Dictate at a natural speed, with pauses, and do not lose words. | In progress | #85 gives a 1200 ms end silence while earshot waits for text. #86 removes the result sound while earshot waits for words. Measure again after the Hex study. |
| 3 | 2026-11-03 | Wake phrase that works with any microphone and position. | Open | Live test: the voice score fell from 0.73 to 0.10 after a change of microphone or position. Ideas: store the input device with the enrolment and warn when it changes; more enrolment takes; teach again from the menu in one click. |
| 4 | 2026-11-03 | A short follow-up ("send", "yes") must pass the voice check. | Open | Short turns score low on voice. Do not lower the bar, because the always-on send needs it (D-12). Measure the scores of a spoken "send" first. |
| 5 | 2026-11-03 | Always-on dictation with no "type": a long sentence with no command word does nothing today. | Open | Live test at 19:03: 28 words, about 14.5 s, gave "not a command". Option: in a focused text field, offer the text as dictation. Needs the owner's choice, because it can type speech that was not meant for earshot. |
| 6 | 2026-11-02 | Jev sees the screen: a click fallback with one picture of the front window. | Open | Built (#49, #59) and off by default. The owner has not tested it live yet. |
| 7 | 2026-11-01 | Own decision model: the command vocabulary is small, so a small local model could replace the rules and Jev. | Later | The owner chose "no local small model now". Collect the activity log as training data first. |
| 8 | 2026-11-02 | One install of earshot that the Dock and "Start at login" always find. | Open | Old copies in `app/build/old-*` and `~/projects/earshot` were opened by mistake. Option: install to `/Applications`, and keep backups as zip files only. |

## Done

| Date | Idea | Pull request |
|---|---|---|
| 2026-11-02 | No hard-coded app scripts: targets and verbs from the screen, menus, chats and apps. | #41 and later |
| 2026-11-02 | Wake phrase and owner voice check for always-on mode. | #64, #71, #73, #78 |
| 2026-11-02 | Menu commands by voice, and tab titles that do not block a tab switch. | #43, #46, #58 |
| 2026-11-03 | Say "type", then the text. | #72, #82 |
| 2026-11-03 | "send" alone after typing, in always-on mode. | #75, #77 |
| 2026-11-03 | A start sound as Hex has, and a sound for each result. | #85 |
| 2026-11-03 | Less memory: Parakeet mapped from disk (904 MB to about 200-300 MB). | #80 |
| 2026-11-03 | Plain words go into the focused box with the hold key. | #68 |
