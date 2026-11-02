# earshot-probe (E0)

earshot-probe is the E0 viability probe. It tests one question: can a spoken sentence put the cursor in the correct chat box in less than 1 s, on this Mac, with no cloud service and no script for each app?

The protocol and the pass marks are in [docs/experiments/E0-viability.md](../docs/experiments/E0-viability.md).

## What the probe uses

- Apple frameworks only: Speech, AVFoundation, Accessibility, AppKit and the Carbon hot-key service.
- No third-party package, no model server and no network service.
- The app table is data in [apps.json](apps.json) (R-MT-2).
- Your test chats are in `people.json`. It holds names only. Git ignores this file.
- Each app opens a chat through its own search: the probe types the name and picks the top result. No app needs a phone number or an email address.
- Messages opens the chat through File > New Message (Command-N): the probe types the name in the "To:" field and picks the first suggestion.
- If an app row has no search keys, the probe finds the search field through accessibility and focuses it.

## Safety

> **WARNING:** A Return key press in a message box sends the message. You cannot undo a sent message.

The probe obeys these rules (R-NV-5, R-ON-5):

1. It never presses Return or Send in a message box.
2. It presses Return only to open a search result, one time for each command. Before the press, it checks the focus:
   - The search keys must move the focus to a new field. If the focus does not move, the probe stops and types nothing.
   - If the focus is in a text field, it must be the field that the probe typed the name into. The field must be in the upper part of the window, hold exactly the name, and accept typed text. Its label must not say "message", "reply", "compose", "write" or "send", unless it also says "search".
   - If the focus is not in a text field, it must be on a row of a result list.
   - If the focus is in a message box or on a button, the probe presses Escape and stops.
3. It types text only into your own chats, and only when the chat name on screen is exactly your name. For other people, it only focuses the box.
4. It types only into an empty box, or into a box that holds earlier "[earshot test]" text.
5. It removes control characters from all typed text.
6. It saves no audio.

## Procedure

Do these steps in your terminal app (for example Ghostty), in `~/projects/earshot/probe`.

### Setup (one time)

1. Run `swift run earshot-probe setup`. Give your name as Slack shows it, and up to 5 contact names.
2. Run `swift run earshot-probe check`.
3. If Accessibility is off, turn on your terminal app in System Settings > Privacy & Security > Accessibility.
4. Quit the terminal app, open it again, and run `swift run earshot-probe check` again.
5. If macOS asks for the microphone, click Allow.

### Part A: typed commands (about 10 minutes)

1. Open Slack and Messages. Sign in to each app.
2. Run `swift run earshot-probe bench`.
3. Do not touch the keyboard or the mouse until the report shows.

To test one app only, run `swift run earshot-probe bench slack 3`.

### Part B: voice commands (about 10 minutes)

1. Run `swift run earshot-probe listen`.
2. Read the next line in the note at the top right of the screen.
3. Hold Control-Option-E, say the line, and release the keys.
4. If a result is wrong, press Control-Option-N.
5. Repeat steps 2 to 4 until the script ends.
6. Press Control-Option-Q to end the session.

### Report

Run `swift run earshot-probe report`. The report shows the result for each app.

## Other commands

| Command | What it does |
| --- | --- |
| `swift run earshot-probe inspect --front` | Reads the menu shortcuts and the text fields of each app. It brings each app to the front, then brings back your app. It presses no key and types nothing. |
| `swift run earshot-probe route "Slack me, running late"` | Shows how the router reads a command. It does no action. |
| `swift run earshot-probe run "Slack me, running late"` | Runs one typed command. |
| `swift run earshot-probe transcribe file.aiff` | Transcribes an audio file and shows the time. |
| `--engine dictation` | Uses the dictation model in place of the general model. |
| `--locale en-IN` | Uses a different speech locale. |

## E1: generic router

E1 tests a router with no hand-written app rows and no hand-written names. See [docs/experiments/E1-generic-router.md](../docs/experiments/E1-generic-router.md).

> **CAUTION:** `e1-try` and `e1-run` send the command words, your name and the chat names on the short list to Jev, a cloud service. They send no audio. Use them only for E1.

| Command | What it does |
| --- | --- |
| `swift run earshot-probe catalogue` | Builds `logs/catalogue.json` from the menu bars of the running apps. It reads only. |
| `swift run earshot-probe index` | Reads the chat names in each chat app's sidebar into `logs/index.json`. Add `--front` if an app shows no names. Add `--debug` to see each name and where it came from. |
| `swift run earshot-probe e1-make` | Makes `logs/e1-commands.json`: about 50 test commands with their correct answers. |
| `swift run earshot-probe e1-try "message Ravi on Slack"` | Shows the short list, the rules answer and the Jev answer for one command. Put `--no-jev` after the words to leave out Jev. |
| `swift run earshot-probe e1-run` | Routes all test commands with the rules, with Jev, and with the rules first and Jev only when the rules are unsure. Add `--no-jev` to use the rules only. |
| `swift run earshot-probe e1-search [app...]` | Types names into each chat app's own search, reads the result names, then clears the field and presses Escape. It never presses Return. Do not touch the keyboard or the mouse while it runs. |
| `swift run earshot-probe e1-open [app] [runs]` | Opens your own chat with the generated rows and focuses the box. It types nothing. Do not touch the keyboard or the mouse while it runs. |

The Jev key comes from `TYPESAFE_API_KEY`, else from `~/.config/jev-qa/env`. The probe never prints or saves the key.
