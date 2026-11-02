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

- Part A: `earshot-probe bench`. Typed commands into the owner's own chats, 10 for each app (3 for Mail). Every second command starts from Finder.
- Part B: `earshot-probe listen`. 40 spoken commands from a script, 10 for each app, then 5 in the owner's own words. Real contacts get focus only.
- Speech: Apple SpeechTranscriber (macOS 26, on device), with fast results and the test names as context hints. The second engine is DictationTranscriber.

Stages in the log, in milliseconds after the start (Part B: after key release):

| Stage | Meaning |
| --- | --- |
| `text` | Final transcript ready |
| `route` | Router done |
| `keys_up` | Held modifier keys released (only if the probe had to wait) |
| `front` | Target app has keyboard focus |
| `chat` | Switcher Return pressed (Slack only) |
| `focus` | Message box has focus |
| `checked` | Chat name check done |
| `typed` | Text shows in the box |

## 4. Environment

- Mac Mini, Apple M4 Pro, 24 GB, macOS 26.6.2.
- Xcode with the macOS 27 SDK, Swift 6.4. Deployment target macOS 26.0.
- Slack 4.52.178 (Electron), WhatsApp 26.42.79, Messages 26.0, Mail 16.0.

## 5. Results

Not run yet.

## 6. Decision

Not made yet.
