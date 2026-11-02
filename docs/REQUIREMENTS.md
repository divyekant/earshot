# earshot requirements

This document records the requirements of the owner (the single user of earshot). The requirements come from a design conversation on 2026-11-01. Each requirement has an ID. Use the ID in commits, issues and tests.

Priority values:
- **Must**: earshot is not useful without this requirement.
- **Should**: add this requirement in the first usable version if possible.
- **Could**: add this requirement later.

## 1. Problem

The owner wants to type less. Dictation tools, for example Wispr Flow, VoiceInk and Handy, only type into the text box that already has focus. The owner must still use the mouse or keyboard to find the app, the conversation and the text box. The owner wants voice to be the main interface of the Mac, not only a typing aid.

## 2. Core flow

The owner described this flow:

1. Press one button, or say the wake phrase (see R-ON-1).
2. Say something.
3. earshot changes focus to the correct screen.
4. earshot focuses the correct text box.
5. The owner dictates text.
6. earshot enters the text in the text box.

## 3. Requirements

### 3.1 Listening and triggering

| ID | Requirement | Priority |
|---|---|---|
| R-ON-1 | earshot listens all the time. A command starts when the owner says the wake phrase (default "hey jarvis"). No key press is needed. Speech without the wake phrase does not start a command. Changed on 2026-11-02 from "no wake word" (D-11). | Must (final) |
| R-ON-2 | earshot acts only on speech that is for it: speech after the wake phrase, or a follow-up command in the owner's voice up to 5 s after a command. Talk to a person in the room or in a call does not start a command (D-11). | Must (final) |
| R-ON-3 | earshot ignores voices that are not the owner's voice, for example TV, calls and other people. The owner teaches earshot the voice with 5 wake phrases. Until the owner does this, any voice can wake earshot, and the management window says so (D-11). | Must |
| R-ON-4 | A push-to-talk key is available. Use it in the first version, and keep it as a fallback. | Must (MVP) |
| R-ON-5 | A false trigger must not cause an action that cannot be undone, for example a sent message. | Must |

### 3.2 Speed

| ID | Requirement | Priority |
|---|---|---|
| R-SP-1 | From the end of speech to a focused text box takes about 1 s or less. | Must |
| R-SP-2 | earshot does not use an AI agent loop that calls a large model for each step. The owner rejected the latency of these agents. | Must |
| R-SP-3 | A voice click takes less than 500 ms from the end of speech. | Should |

### 3.3 Navigation and text entry

| ID | Requirement | Priority |
|---|---|---|
| R-NV-1 | earshot opens or switches to the app that the owner names. | Must |
| R-NV-2 | earshot opens the conversation, channel or contact that the owner names, for example "Slack Ravi". | Must |
| R-NV-3 | earshot puts the focus in the main text box of that screen. | Must |
| R-NV-4 | earshot enters dictated text in the focused text box. A command can include the text: "Slack Ravi, running late". | Must |
| R-NV-5 | earshot does not press Send unless the owner says so, for example "send" or "click Send". | Must |
| R-NV-6 | First apps to support: Slack, WhatsApp, Messages, Mail. | Must |
| R-NV-7 | "Open <web address>" opens the address in the default browser, for example "open hn.com" or "go to news dot ycombinator dot com". earshot opens only http and https addresses, and presses no key. | Should |

### 3.4 Voice clicks

The owner sees the screen and tells earshot what to do. earshot does not need to "think".

| ID | Requirement | Priority |
|---|---|---|
| R-CL-1 | "Click <label>" clicks the element with that visible label in the front window. | Must |
| R-CL-2 | "Click the <nth> <item>" clicks an item by its position, for example "the second email". | Should |
| R-CL-3 | "Show numbers" shows numbers on clickable elements. "Click <n>" then clicks that element. | Should |
| R-CL-4 | If an app has poor accessibility labels, earshot finds the text on the screen with OCR. | Should |

### 3.5 Upkeep

| ID | Requirement | Priority |
|---|---|---|
| R-MT-1 | earshot does not use a hand-written script for each app. The owner does not want to maintain a script for each app. | Must |
| R-MT-2 | To add support for an app, add one row of data, not new code. | Must |
| R-MT-3 | Generic behavior, for example focusing a text box or clicking a label, works in apps that have no data row. | Should |

### 3.6 Models and resources

| ID | Requirement | Priority |
|---|---|---|
| R-MD-1 | All speech processing runs on the Mac. Audio never leaves the Mac. Decisions run on the Mac by default. The owner can switch on Jev (tier 2) in the app. Then, only when the rules are unsure, earshot sends the command words and the short list of candidate labels to Jev, as text. The owner can also switch on "Jev sees the screen", a separate setting that is off by default (D-10). Then, only when a hold-key click finds no target, earshot sends the command words and one picture of the front window to Jev. It never sends a picture of a sign-in, code or payment page. | Must |
| R-MD-2 | Use only small models. A model of 30B parameters is not necessary and is not wanted. | Must |
| R-MD-3 | earshot uses little memory. Target: less than 2 GB total while idle and listening. Wispr Flow uses about 1.4 GB on this Mac, for comparison. | Should |
| R-MD-4 | earshot uses open-source components where possible. | Should |
| R-MD-5 | earshot understands English. The owner also uses Hinglish (Hindi mixed with English) in Wispr Flow. | Must (English); Should (Hinglish) |
| R-MD-6 | earshot does not use MCP servers to act in apps. It operates the user interface directly. | Must |

### 3.7 Feedback

| ID | Requirement | Priority |
|---|---|---|
| R-FB-1 | earshot shows visual feedback, for example a small note "→ Slack · Ravi". The owner reads faster than they listen. | Must |
| R-FB-2 | Spoken replies (talkback) are optional and off by default. | Could |

## 4. Out of scope

- Multi-step tasks that need reasoning, for example "reply to the person who asked about the invoice". These tasks need a large model and are slow. They are not part of earshot.
- Physical devices other than the Mac Mini.
- Any cloud transcription service.

## 5. Open questions

| ID | Question | How to answer it |
|---|---|---|
| Q-1 | How often does the wake phrase fire by mistake, and how often does it miss the owner? Which voice score separates the owner from other voices? | Log the wakes, the rejected wakes and the voice scores of one week of real use (DESIGN.md, Phase 3). |
| Q-2 | Which speech-to-text model handles Hinglish well enough? | Test Nemotron-3.5 streaming and the community Hinglish fine-tunes on the owner's own audio. |
| Q-3 | How long does an accessibility search take in Slack and other Electron apps? | Measure in Phase 0. |
| Q-4 | Can one command include the message text, or must the owner pause after the target? | Test both in Phase 1. |
