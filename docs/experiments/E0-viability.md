# E0: viability probe ("one sentence to the box")

Status: built, not run yet. Plan date: 2026-11-01.

E0 replaces step 1 of Phase 0 in [DESIGN.md](../DESIGN.md). It measures the numbers that decide viability directly, with no setup of other projects.

## 1. Question

Can one spoken sentence put the cursor in the correct message box, on this Mac, with these limits?

- No cloud service (R-MD-1).
- No large-model agent (R-SP-2). The router uses rules only.
- No script for each app (R-MT-1). App support is data in `probe/apps.json`.
- No Send key press (R-NV-5, R-ON-5).

## 2. Checks and pass marks

The time counts only when the app is already open. The probe logs the time for a closed app, but that time does not count.

| Check | Measure | Go | Change the design | Stop |
| --- | --- | --- | --- | --- |
| Reach (R-NV-1 to R-NV-3) | The probe reads the front app, the chat name on screen and the focused field | 9 or more of 10, in each app | 7 to 9 of 10 | Under 7 of 10 in 2 or more apps |
| Speed (R-SP-1) | Time from key release to focused box: median and slowest 1 in 10 | Median under 1.0 s | 1.0 s to 2.0 s | Over 2.0 s after the obvious fixes |
| Hearing (R-MD-5) | Routed app and person against the script line | 9 or more of 10 | 7.5 to 9 of 10: try the second engine | Under 7.5 of 10 with both engines |
| Safety (R-NV-5, R-ON-5) | Messages sent, or text typed in a wrong place | 0 | Not allowed | 1 or more |
| Worth it | The owner's answer after the session | Yes | "Yes, if..." | No |

The 1 s mark is an upper limit, not the goal. The owner counts about 100 ms as instant. The log keeps the time of each stage, so later work can cut the slowest stages.

## 3. Method

- Apps: Slack and Messages. Each app opens a chat through its own search: the probe types the name and picks the top result. The test data is names only. WhatsApp is out of E0 (see 5.4).
- Part A: `earshot-probe bench`. Typed commands into the owner's own chats, 10 for each app. Every second command starts from Finder.
- Part B: `earshot-probe listen`. 19 spoken commands from a script: 10 for Slack, 4 for Messages, then 5 in the owner's own words. Real contacts get focus only.
- Speech: Apple SpeechTranscriber (macOS 26, on device), with fast results and the test names as context hints. The second engine is DictationTranscriber.

Stages in the log, in milliseconds after the start (Part B: after key release):

| Stage | Meaning |
| --- | --- |
| `text` | Final transcript ready |
| `route` | Router done |
| `keys_up` | Held modifier keys released (only if the probe had to wait) |
| `front` | Target app has keyboard focus |
| `chat` | Return pressed on the top search result |
| `focus` | Message box has focus |
| `checked` | Chat name check done |
| `typed` | Text shows in the box |

## 4. Environment

- Mac Mini, Apple M4 Pro, 24 GB, macOS 26.6.2.
- Xcode with the macOS 27 SDK, Swift 6.4. Deployment target macOS 26.0.
- Slack 4.52.178 (Electron), WhatsApp 26.42.79, Messages 26.0.

### 4.1 Change on 2026-11-02: names only

The first plan opened WhatsApp, Messages and Mail chats through links. The links need a phone number or an email address for each person. The owner found this setup too slow. Now each app opens the chat through its own search, as Slack does. This is also closer to the final design: the owner says a name, not a number. Mail is out of E0, because a new email needs an address.

The probe presses Return only on a search result (see the safety rules in [probe/README.md](../../probe/README.md)). It types text only when the chat name on screen is exactly the owner's name.

## 5. Results

### 5.1 Before the session: speech from files (2026-11-02)

Audio files made with `say`, no microphone. The time is from the start of analysis to the final text, for the whole file.

| Engine | File | Text | Time |
| --- | --- | --- | --- |
| SpeechTranscriber | "Slack me, running late" (first run, model just installed) | "Slack me running late." | 176 ms |
| SpeechTranscriber | "WhatsApp Ravi" | "WhatsApp Ravi." | 60 ms |
| SpeechTranscriber | "Email me, call me after lunch" | "Email me, call me after lunch." | 73 ms |
| SpeechTranscriber | "Slack me, running late" (warm) | "Slack me running late." | 56 ms |

The router read all three transcripts correctly. The model download took about 2 s.

DictationTranscriber with the `.shortDictation` preset sent no final result, so the first build returned empty text. `.progressiveShortDictation` and `.longDictation` send a final result. The dictation engine can drop the last word when the audio stops right after the speech; the transcriber did not. The probe now adds 300 ms of silence at key release and keeps the last volatile text if no final result arrives.

### 5.2 Part A, first run (2026-11-02)

The probe ran on the owner's Mac through a remote session, with the owner's approval. Nothing was sent.

Focus-only check, one command for each app:

| App | Result | Cause |
| --- | --- | --- |
| Slack | Pass, 656 ms | Your DM opened through Command-K. The header showed the name before the window title changed. |
| WhatsApp | Fail at the search step | After Command-F, the focus is an AXStaticText with the AXSearchField subrole. The probe accepted only editable text roles. |
| Messages | Wrong chat | Search, Down and Return did not open the owner's chat. The probe still reported a pass, because it counted an unknown chat as a pass. |

Part A, Slack, 10 commands into the owner's own DM (log `e0-bench-20261101-165936.jsonl`):

| Reach | Verified | Median to focused box | Slowest 1 in 10 |
| --- | --- | --- | --- |
| 10 of 10 | 10 | 466 ms | 497 ms |

Stages of a typical Slack command: front 3 to 59 ms, Return in the switcher at about 380 ms, focused box at about 470 ms. The switcher stage includes a fixed 250 ms wait (`settle_ms`). That wait is the first target for the 100 ms goal.

Other findings:
- The test text was typed into the owner's own DM, but the probe did not delete it. The delete step looked for the focused element, not the box that it typed into.
- One command waited 1.5 s for modifier keys. A failed command left the Command flag set, because the probe sent no event that releases it.

Fixes in the next build:
- WhatsApp: accept an element with the AXSearchField subrole as the search field.
- Messages: open the chat through File > New Message (Command-N) and the "To:" field.
- Reach counts a command only when the chat name is on screen. The chat check leaves out the field that holds the typed name.
- The delete step uses the box that the probe typed into, and it accepts only test text in the box.
- After each key combination, the probe releases the modifier flags.

### 5.3 Part A, second run (2026-11-02)

| App | Reach | Median | Slowest 1 in 10 | Notes |
| --- | --- | --- | --- | --- |
| Slack | 10 of 10 | 468 ms | 490 ms | The test text was not deleted again: the box held 53 characters for two 27-character lines. |
| Messages | 10 of 10 | 1813 ms | 1850 ms | Command-N and "To:" reach the chat at about 700 ms. The probe then waited 700 ms for the app to focus the box, 300 ms for the accessibility focus, and then clicked the box. |
| WhatsApp | not run | - | - | The guard stopped Return: after Down, the focus was an AXGroup (iOSContentGroup), not a list row. This is correct guard behavior. |

Fixes in the next build:
- The focus step remembers, for each app, which method worked. If the app did not focus the box by itself, the probe does not wait for it again. The first wait is now 500 ms, and the accessibility wait is 150 ms.
- WhatsApp: press Return in the search field (no Down).
- The delete step compares word by word, so small changes to the text by the app do not block it.

### 5.4 WhatsApp is out of E0 (2026-11-02)

The search for the owner's full name found no WhatsApp chat with that name. Return opened the top result, a message hit in another person's chat. The chat check failed, so the probe typed nothing. The owner chose to leave WhatsApp out of E0 and not to give the name of the WhatsApp self chat. The row stays in `probe/apps.json` with `"enabled": false`.

What E0 learned about WhatsApp (version 26.42.79, a Catalyst app):
- File > Search is Command-F. The search field is an AXStaticText with the AXSearchField subrole.
- Search results are AXButton and AXStaticText rows, not AXRow. Down moves the focus to an AXGroup (iOSContentGroup).
- The chat name is the description of the header button (identifier `NavigationBar_HeaderViewButton`), at 2 % of the window height.
- A search for a name also lists message hits. If no chat has that name, the top result can be another chat. A later design needs a check of the result type before Return.

### 5.5 Part B

Not run yet.

## 6. Decision

Not made yet.
