# earshot build plan

The experiments E0, E1 and E2 showed that earshot is viable. This plan builds the product. It splits the work into tasks T0 to T8, so that threads can work in parallel.

## 1. The product

- One native Mac app: a menu-bar helper and a management window.
- The hold key is the input for now (R-ON-4). Always-on is an option in the app, off by default (R-ON-1).
- earshot is generic. App support is catalogue data that earshot builds from the menus of each app. Names come from the app sidebars, the app search and, optionally, Contacts. There is no code for one app and no hand-written list of people (R-MT-1, R-MT-2).
- The probe (`probe/`) stays as the lab. Do not change it for product work.

## 2. Tasks

| Task | Scope | Folder that the task owns | Depends on |
|---|---|---|---|
| T0 Foundation | Package with every module target, EarshotCore protocols and types, settings store, activity log, safety policy, app shell | `app/Package.swift`, `app/Sources/EarshotCore`, `app/Tests/EarshotCoreTests`, this file | — |
| T1 Speech | Apple SpeechTranscriber engine and Parakeet engine (transcribe.cpp, model kept loaded). Engine "auto": Parakeet if its model file exists, else Apple. Partial text. Audio after key release. | `app/Sources/EarshotSpeech`, `app/Tests/EarshotSpeechTests`; also the TranscribeCpp binary target in `app/Package.swift` | T0 |
| T2 Router | Rules and fuzzy match from E1 and E2. Name match by sound ("Manal" → Mrinal). Exact match for labels that are mostly numbers. Tier-2 Jev client (opt-in, 1 s budget, rules answer as the fallback). | `app/Sources/EarshotRouter`, `app/Tests/EarshotRouterTests` | T0 |
| T3 Actions | Open app, open chat (switcher or link from the catalogue), focus the message box, type, web click (AXPress if the element offers it, else a click after a hit test), scroll, back. "Show numbers" on clickable elements (R-CL-3). OCR fallback with Apple Vision for apps with poor labels (R-CL-4). All rules of SafetyPolicy. | `app/Sources/EarshotActions`, `app/Tests/EarshotActionsTests` | T0 |
| T4 Discovery | Catalogue from the menus (whole words, owner approval). Name index from sidebars, app search (with the echo and label filters) and optional Contacts. Refresh. | `app/Sources/EarshotDiscovery`, `app/Tests/EarshotDiscoveryTests` | T0 |
| T5 Input | Hold key (configurable; default right Option alone, key code 61, read with a flagsChanged monitor). Always-on: speech detection, end of turn, "for me?" gate. A false trigger never does an action that cannot be undone (R-ON-5). | `app/Sources/EarshotInput`, `app/Tests/EarshotInputTests` | T0, T1 |
| T6 Management window and note | Tabs: General, Apps, Names, Activity, Permissions, Test. Jev key in the Keychain. The feedback note on screen (FeedbackSink, R-FB-1). Uses EarshotCore types only. | `app/Sources/EarshotUI`, `app/Tests/EarshotUITests` | T0 |
| T7 Integration | Connect the modules in EarshotApp. App bundle, Info.plist usage text, signing, start at login. Live tests on the Mac. | `app/Sources/EarshotApp`, `app/scripts` | T1 to T6 |
| T8 Docs | README, user guide, design and decisions updates. | `README.md`, `docs/` | T7 |

T0 freezes the protocols in `app/Sources/EarshotCore/Protocols.swift` and the types in `app/Sources/EarshotCore/Types.swift`. If a task needs a change to them, ask the coordinator first.

T0 declares every module target in `app/Package.swift`. Threads do not edit `app/Package.swift`. The one exception: T1 adds the TranscribeCpp binary target and its linker settings.

## 3. Rules for every thread

1. Change only the folder that your task owns. Use the types and protocols of EarshotCore. Do not import another task's module.
2. Add unit tests for the logic in your folder.
3. Record latency numbers for every change to the command path in the pull request (AGENTS.md).
4. Write docs, comments and commit messages in Simplified Technical English.
5. No cloud service by default. Jev is the only exception: opt-in tier 2, off by default, text only, 1 s budget (R-MD-1, D-9). Audio never leaves the Mac.
6. Never press Return or a Send button unless the owner says "send" (R-NV-5, R-ON-5). Use `SafetyPolicy`.
7. App support is data, not code. Do not add an `if app == "slack"` branch (R-MT-1, R-MT-2).
8. Work in your own git worktree on the Mac, for example `~/projects/earshot-t1`. Never build in `~/projects/earshot`, so that builds do not collide.
9. Live tests that press keys or click run one at a time, and only after the owner says "go".
10. Live tests type only into the owner's own chats. For other people, a test only puts the cursor in the message box.

## 4. Toolchain

- Swift tools 6.0, macOS 26, Swift 5 language mode. Swift 5 mode keeps strict concurrency checks from slowing the threads. Change it in a later task, not now.
- The Mac: Apple M4 Pro, macOS 26.6.2, Xcode with the macOS 27.0 SDK, Swift 6.4.
- Build and test: `cd app && swift build && swift test`.

## 5. Signing

macOS keeps the Accessibility and Microphone permissions only while the code signature stays the same. An ad-hoc signature changes with each build, so macOS asks again after each rebuild. T7 signs with a stable identity when `security find-identity -v -p codesigning` lists one (for example Apple Development). If there is none, T7 signs ad hoc and prints a warning.
