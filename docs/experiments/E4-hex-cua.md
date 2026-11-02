# E4. Hex + Cua Driver and Hex + AX against earshot

Date: 2026-11-02. Decision record: [D-7](../DECISIONS.md). Requirements: R-SP-1, R-SP-2, R-NV-3, R-NV-5, R-MD-6.

## 1. Question

Can Hex (speech) plus Cua Driver, or Hex plus the macOS Accessibility (AX) API, do the earshot use case better than earshot? No model runs between the transcript and the action.

## 2. Answer

No. earshot stays as it is.

- Hex + Cua Driver is slower and less reliable. A click on a web page took 1.8 to 2.2 s. One Cua click reported success, but the page did not change. Cua shows no keyboard focus, so a chat command cannot prove where its text goes.
- Hex + AX is about as fast as earshot, because it uses the same method. It has fewer parts: no sound match, no app table, no name index. Each fault that it hit in E4 is already handled in earshot.
- Hex speech is the one part that is better today. Hex runs Parakeet in about 155 ms on the test Mac. earshot uses Apple speech by default (PR #32), which made more word errors in E2.

## 3. Method

The owner's Mac mini (M4 Pro, 24 GB, macOS 26) ran all steps. Hex was not rebuilt.

| Part | What it does in E4 |
|---|---|
| Hex 3.2.0 (anomalyco/hex, MIT) | Hold key fn, speech to text with Parakeet, paste. After each dictation, Hex runs the "transformations" of `~/.config/hex/hex.config.ts` (QuickJS). |
| `hexact.ts` | A Hex transformation. It sends the transcript to `hexact` with `execFile` and pastes what `hexact` prints. Hex runs a program only after the owner clicks Allow in its Output pane. |
| `hexact` (Swift) | The glue. A fixed grammar gives one verb and one target. Then one of two executors acts. |
| Executor `ax` | AX and CGEvent calls in the `hexact` process. |
| Executor `cua` | One `cua-driver call <tool>` for each step, to the Cua Driver 0.38.0 daemon. |

The bench typed 19 commands into `hexact`, one process for each command, in the same order for both executors:

- Calculator: open it, click a key.
- Chrome: open Hacker News (HN), click links, go back, scroll, open example.com.
- Blocked commands: "send", "click send", "click submit".
- Chats: a draft "test from hexact" in the owner's own Slack and Messages chats. The glue never presses Return in a message box.

After each case, a read-only AX program recorded the front app, the window title, the focused field and the Calculator display. earshot did not run in the bench. Its times come from its activity log of live voice commands on the same Mac, on other commands and pages.

The glue code, the result tables and the bench log (own names removed) are on the owner's Mac in `~/projects/hex-cua-exp/final/`. They are not in this repository.

## 4. Results per case

| Case | Said | Hex + AX | Hex + Cua |
|---|---|---|---|
| a1 | Open Calculator | Pass | Pass |
| d1 | Click seven | Pass | Pass |
| d2 | Click all clear | Fail: the key says "Clear" while a number shows | Fail: same |
| a2 | Open Chrome | Pass | Pass |
| b1 | Open news dot ycombinator dot com | Pass | Pass |
| c1 | Click new | Pass | Fail: Cua reported the click, the page did not change |
| c5 | Go back | Pass | Unclear: it follows the failed c1 |
| c2 | Click past | Pass | Pass |
| c6 | Scroll down | Ran, not checkable: Chrome shows no scroll value to AX | Same |
| c7 | Scroll up | Ran, not checkable | Same |
| c3 | Click ask | Pass | Pass |
| c4 | Click show | Pass | Pass |
| c8 | Click submit | Pass: blocked as a risky label | Pass: blocked |
| b2 | Go to example.com | Pass | Pass |
| a3 | Open Cloud (meant: Claude) | Fail: no sound match | Fail: same |
| e3 | Send | Pass: blocked | Pass: blocked |
| e4 | Click send | Pass: blocked | Pass: blocked |
| e1 | Slack me, test from hexact | Pass after a safety fix: draft in the owner's own chat, not sent | Not run: the safety check on the Mac refused the step |
| e2 | Messages me, test from hexact | Fail: the text went into the To field. Fixed, not run again | Not run |
| All | | 14 pass, 3 fail, 2 not checkable | 11 pass, 3 fail, 1 unclear, 2 not checkable, 2 not run |

earshot passes "Open Cloud" with its sound match (2 of 2 in a live test on 2026-11-02). Nothing was sent in any chat during E4.

## 5. Speed

Median time from the typed command to the end of the action (last run of each executor, one sample for each case):

| Command kind | Hex + AX | Hex + Cua | Cua / AX |
|---|---|---|---|
| Open a web address (2 cases) | 77 ms | 172 ms | 2.2 |
| Open an app (2 cases) | 115 ms | 941 ms | 8.2 |
| Click in Calculator (1 case) | 108 ms | 1,458 ms | 13.5 |
| Click on HN (4 cases) | 323 ms | 1,915 ms | 5.9 |
| Go back (1 case) | 35 ms | 559 ms | 16.0 |
| Scroll (2 cases) | 69 ms | 879 ms | 12.7 |
| Slack, own chat (1 case) | 863 ms | not run | |

The Cua cost is in the action tools, not in the process start. A bare call (`get_screen_size`) took 15 ms median. `click` took 1,135 ms median, `scroll` 779 ms, `get_window_state` 627 ms, `bring_to_front` 620 ms and `list_windows` 83 ms.

earshot, live voice commands on 2026-11-02 (median, from key release):

| Stage | Click (7 commands) | Open an app (4 commands) |
|---|---|---|
| Speech (Apple) | 177 ms | 187 ms |
| Route | 7 ms | 3 ms |
| Screen read | 27 ms | 22 ms |
| Action | 6 ms | 57 ms |
| Total | 249 ms | 285 ms |

- The earshot screen read takes 22 to 27 ms. The glue walked the whole HN page (2,160 elements) in 250 to 310 ms. This walk is most of its click time.
- With Hex speech added (about 155 ms), a Hex + AX click on HN takes about 0.5 s.
- The earshot chat action took 1,003 ms median (4 commands on 2026-11-01 and 2026-11-02).

## 6. Speech

| | Hex 3.2 | earshot (default since PR #32) |
|---|---|---|
| Engine | Parakeet Unified English (transcribe.cpp) | Apple speech. Parakeet only when the memory pressure is normal. |
| Speech time on the test Mac | 155 ms median, 198 ms p90 (inference, 21 dictations of 3 to 60 s) | 177 to 187 ms median (live commands on 2026-11-02) |
| Key release to text | 231 ms median, 310 ms p90 (to the paste) | See the totals in section 5 |
| Word error rate in E2 (126 `say` files) | 14.9 % (Parakeet) | 18.8 % (Apple SpeechTranscriber) |

earshot changed its default to Apple speech because its own Parakeet stage took 0.4 to 6.9 s on this Mac. The Mac was short of memory, and macOS swapped the model out between commands. Hex keeps its model loaded and did not show this in its log. If both apps load Parakeet, the Mac holds two copies of the model.

New fact: a Hex 3.2 transformation can give the transcript to another program. E2 assumed that Hex had no way to give its text to earshot.

## 7. Setup and reliability

| | Hex + AX | Hex + Cua | earshot |
|---|---|---|---|
| What to install | Hex and the glue | Hex, the glue, and Cua Driver from an outside installer | earshot |
| macOS permissions | Accessibility for Hex | Accessibility for Hex, plus Accessibility and Screen Recording for Cua Driver | Accessibility, Microphone, Speech Recognition |
| Owner steps | Click Allow once in Hex | The same, plus the install and two grants. The first grant dialog timed out. | Grant the permissions once |
| Processes for one command | Hex and one glue process | Hex, one glue process, one `cua-driver` process for each step, and the daemon | earshot |

Cua Driver 0.38 refused the `post_action_wait` argument. It needed a process ID for key events. It refused `bring_to_front` with a process ID alone when an app had several windows, and it found no Chrome window on another Space. The glue needed 4 fixes for this version.

## 8. Faults in the glue

The glue hit 7 faults. Two of them stopped the run for safety. earshot already handles each fault that applies to it.

| Fault | Effect | In earshot |
|---|---|---|
| The system-wide AX read of the focused app failed (-25204) | "Open Calculator" waited 10 s | `AX.frontPid` falls back to `NSWorkspace`, which is current in an app. |
| A key event with the Command flag, but no Command key-up | Command stayed down for the whole system | `Events.press` sends a flags-changed event with no flags (E0). |
| `NSWorkspace` state does not change in a command-line program without a run loop | "Open Chrome" was not seen in front | Not affected: earshot is an app. |
| Safety stop: the chat flow took the focused message box for the search field | The owner's name was typed and Return was pressed. Where the name went cannot be proved. No sent message was found. | `returnIsSafe` checks the focused field, its role and its value before Return. |
| The window title was read before the chat switch finished | The read-back failed on the correct chat | earshot waits for the switcher results and the chat name. |
| Safety stop: `AXFocused` on the Messages message field did not move the keyboard focus | The draft went into the To field | `focusComposer` checks the real focus, then clicks, else stops. |
| Cua shows no keyboard focus | A chat step through Cua cannot prove where the text goes | Not used by earshot. |

## 9. Decision

1. Cua Driver: not adopted. D-7 stands, now with measurements.
2. Hex + AX: not adopted. It is a second copy of the earshot method, with fewer parts.
3. Hex speech: no change now. A later test can send Hex text to the earshot router through a transformation. Open points: two apps with two hold keys, the Allow step in Hex, and the memory that Parakeet needs.

## 10. Limits

- No voice run. The owner closed E4 on 2026-11-02 after the typed bench.
- Each case ran once for each executor.
- The earshot and Hex times come from their logs, on other commands and other pages.
- The Cua chat cases and the Messages retry after the fix did not run.
- The Cua daemon started from a Claude Code shell. macOS may have used the permissions of that shell, not those of Cua Driver.
- The grammar of the glue is thin on purpose. A better grammar would close some fails, but then it becomes the earshot router.
