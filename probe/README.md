# earshot-probe (E0)

earshot-probe is the E0 viability probe. It tests one question: can a spoken sentence put the cursor in the correct chat box in less than 1 s, on this Mac, with no cloud service and no script for each app?

The protocol and the pass marks are in [docs/experiments/E0-viability.md](../docs/experiments/E0-viability.md).

## What the probe uses

- Apple frameworks only: Speech, AVFoundation, Accessibility, AppKit and the Carbon hot-key service.
- No third-party package, no model server and no network service.
- The app table is data in [apps.json](apps.json) (R-MT-2).
- Your test chats are in `people.json`. Git ignores this file.

## Safety

> **WARNING:** A Return key press in a message box sends the message. You cannot undo a sent message.

The probe obeys these rules (R-NV-5, R-ON-5):

1. It never presses Return or Send in a message box.
2. It presses Return only in the Slack quick switcher. Before the press, it checks that the focused field holds exactly the name and is in the upper part of the window.
3. It types text only into your own chats. For other people, it only focuses the box.
4. It types only into an empty box, or into a box that holds earlier "[earshot test]" text.
5. It removes control characters from all typed text.
6. It saves no audio.

## Procedure

Do these steps in your terminal app (for example Ghostty), in `~/projects/earshot/probe`.

### Setup (one time)

1. Run `swift run earshot-probe setup`. Answer the questions about your test chats.
2. Run `swift run earshot-probe check`.
3. If Accessibility is off, turn on your terminal app in System Settings > Privacy & Security > Accessibility.
4. Quit the terminal app, open it again, and run `swift run earshot-probe check` again.
5. If macOS asks for the microphone, click Allow.

### Part A: typed commands (about 10 minutes)

1. Open Slack, WhatsApp, Messages and Mail. Sign in to each app.
2. Run `swift run earshot-probe bench`.
3. Do not touch the keyboard or the mouse until the report shows.

To test one app only, run `swift run earshot-probe bench slack 3`.

### Part B: voice commands (about 25 minutes)

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
| `swift run earshot-probe route "Slack me, running late"` | Shows how the router reads a command. It does no action. |
| `swift run earshot-probe run "Slack me, running late"` | Runs one typed command. |
| `swift run earshot-probe transcribe file.aiff` | Transcribes an audio file and shows the time. |
| `--engine dictation` | Uses the dictation model in place of the general model. |
| `--locale en-IN` | Uses a different speech locale. |
