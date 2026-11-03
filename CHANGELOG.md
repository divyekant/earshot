# Changelog

This file lists the changes in each release of earshot.

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). The version numbers follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). [docs/RELEASING.md](docs/RELEASING.md) gives the release procedure.

## [Unreleased]

### Changed

- In always-on mode, the voice of your whole turn now decides, not the wake phrase alone. A longer turn gives a surer score: the limit is 0.35 up to 1 s of speech, and goes up to 0.42 at 2 s. The phrase must still score 0.35 to start a turn. A turn that fails the check is dropped with no note (R-ON-3, R-ON-5, D-11, D-12).
- earshot now keeps one voice profile for each microphone (up to 4). Teach earshot your voice one time on each microphone. When you change the default microphone, always-on uses the profile of that microphone. Your old profile stays (R-ON-3).
- In always-on mode, earshot no longer shows "not sure it was your voice" or plays the failed sound when the voice check drops a wake phrase or a follow-up turn. Other voices, a TV and room sounds set them off too often. The activity log keeps the voice score of each dropped turn (R-ON-3, R-FB-1).

### Fixed

- In always-on mode, earshot no longer drops the next part of your dictation after it typed the first part. A follow-up turn with 1 s of speech or more now also passes if its voice is near the voice of your last turn that passed (score 0.45 or more). "send" alone still needs the full voice check (R-ON-3, R-NV-4, D-11, D-12).
- A result sound no longer starts a follow-up turn in always-on mode: the follow-up window opens when the sound ends, and the detector ignores earshot's own sounds. When earshot waits for your words (after "type", or after a typing), it plays no result sound, so you can go on talking at once (R-ON-1, R-FB-1).
- In always-on mode, a soft end of a word, or speech from a quieter microphone, no longer counts as the pause that ends your turn. A dictated text longer than 15 s is no longer lost: it ends at 60 s with its words (R-ON-1, I-2, I-26).
- With the hold key, earshot keeps more audio at both edges: 450 ms before the key press (was 250 ms) and 200 ms after the release (was 100 ms). So a first or last word said on the key edge is not lost. In always-on mode, the end of a turn no longer waits for more audio, which saves 100 ms (R-SP-1, R-ON-1, I-1).
- "Here at least …" (the wake phrase heard wrong), "I want to …" and "go ahead and …" at the start of a command no longer stop the command (I-29).

### Added

- In always-on mode, a small turn model (Smart Turn v3.2, about 17 MB, one download) listens at the first pause. If it hears that you finished, the turn ends after 300 ms of quiet. If it hears a pause in a sentence, the turn waits up to 2 s (3 s for dictation). No audio leaves the Mac. If the model is not available, the pause rule works as before (R-ON-1, R-MD-1, I-2).
- Several commands in one sentence, for example "click on Projects, click on New, type hello and send". earshot runs the steps in order and reads the screen again before each step. Each step has its own safety checks. If a step fails or earshot is not sure, earshot stops and asks: say "go on", "stop", or the step again within 10 s. At most 10 steps. In always-on mode, a chain never sends (I-28, R-NV-5, R-SP-2, D-12).

## [0.2.0] - 2026-11-03

This release adds the wake phrase and owner voice check for always-on mode, dictation into the focused field, "type" then the text, and "send" said alone after earshot types a message. It also adds sound cues for listen and result. With Parakeet, earshot uses about 700 MB less memory.

### Added

- A short system sound when earshot starts to listen (hold key down, or the wake phrase), and one for each result: done, sent, or failed (not sure, blocked). Turn them off with "Play sounds" in Manage > General. A follow-up turn that earshot drops because it is not sure of your voice now shows a note (R-FB-1).
- Pauses while you dictate: after "type", or after earshot typed in always-on mode, a pause of up to 1.2 s no longer ends your sentence. A sentence that starts within 3 s after earshot typed goes on with the text (R-NV-4, R-ON-1).
- In always-on mode, "send" said alone, in your voice, within 5 s after earshot typed a message, now sends it. Anything else still needs the hold key to send. "Type X and send" never types the word "send": with the hold key, it types and sends; in always-on mode, it types only (R-ON-5, R-NV-5, D-12).
- earshot runs on Intel Macs and on macOS 14 and 15. On these Macs, it uses Apple on-device dictation for speech. No audio leaves the Mac (R-MD-1).
- "Jev sees the screen" now works in the app: an unsure hold-key click that was not blocked can ask Jev with one picture of the front window. It is off by default (R-MD-1, R-NV-5, D-10).
- With the hold key, words with no command word go into the focused text field, for example "Hi, this is a test" after "click the message box". Never into a password field, never on a sign-in, code or payment page, never in always-on mode, and never with Return (R-NV-4, R-NV-5, R-ON-5).
- Say "type", then the text: after a bare "type", the next sentence within 5 s goes into the focused text field, also in always-on mode. A command word in that sentence runs as a command. Never with Return (R-NV-4, R-NV-5, R-ON-5).
- Always-on mode starts on a wake phrase (default "hey jarvis") and checks the owner's voice. Teach earshot your voice with 5 phrases in Manage > General. The models download one time (about 18 MB). No audio leaves the Mac (R-ON-1, R-ON-2, R-ON-3, R-MD-1, D-11).

### Changed

- Always-on mode no longer acts on speech with no wake phrase. The "for me?" text gate is removed (R-ON-1, R-ON-2, D-11).
- The default voice threshold is 0.35, from the live trial. A follow-up turn in another voice is logged with its voice score and no text (R-ON-3, D-11).
- Always-on mode finds the wake phrase by its sound, from the 5 phrases that you say when you teach earshot your voice. Any phrase, name or language works. The log shows the match score of each wake. If you taught earshot before this change, teach it again. Until then, the old spotter listens (R-ON-1, R-ON-3, R-MD-1, D-11).

### Fixed

- After "type", a command word later in the dictated text (for example an app name) is typed as text. Only a first sentence that starts with a command runs as a command (R-NV-4).
- After "type" or after typing, a long sentence that starts within the 5 s window now counts, even if it ends later. Before, a 10 s sentence after "type" was not typed (R-NV-4, R-ON-5, D-12).
- "Yeah, actually let's send" now sends like "send", and "Here, let's open Slack" opens Slack by the rules. The router drops more spoken fillers at the start of a command ("actually", "just", "right", and "here" as the first word) (R-NV-5, R-SP-2).
- With the Parakeet engine, earshot uses about 700 MB less memory. transcribe.cpp 0.4.1 maps the model file instead of a copy in app memory, so macOS can drop the pages under pressure, and Hex and earshot share them (R-MD-3, E2).
- "Type <text> and send" no longer types the words "and send". The router removes a trailing send phrase from the text and tells the app with `sendAfter`. Only an explicit send can press Send (R-NV-5).
- A bare command word such as "type" or "open" no longer presses a menu item that sounds like it. A bare "type" now tells the app that the next turn is the text. "Yeah, let's open the Slack" now opens Slack by the rules (R-NV-5, R-SP-2).
- "Type X" with no box name and no focus types into the message box, not into a search field. "Search for X" still uses the search field. "Click refresh" finds the "Reload" button through a small table of UI word pairs. A pair match is never an exact match, so it never presses a risky label (R-SP-1, R-NV-5).
- If earshot's own Manage window is in front, a voice command now acts on the app that was in front before it. earshot never acts on its own window by voice (R-NV-5).
- "Type X" with no box name now types into the focused text field. "Focus on <box>" clicks the box. "Type X into <box>", "in <box> type X" and "click <box> and type X" type into that box, if the box words match a text field on the screen. A command in a later sentence now works when the first sentence has no command word. Typing never presses Return (R-SP-1, R-NV-5).
- A tab or window title with a word such as "transfer" no longer blocks a switch to that tab. Bookmarks and History menu items are no longer click targets (R-NV-5, R-MT-1).
- A change in the Manage window to the wake phrase, the mode, the hold key or the speech engine now works at once. Before, it worked only after the next restart of earshot (R-ON-1, R-ON-4).
- Always-on mode removes the wake phrase also when speech to text writes it as other words, for example "Here, at least" for "hey atlas". Before, the command failed (R-ON-1, D-11).
- Always-on mode removes the wake phrase by its audio time with Apple speech, so a misheard form such as "Yeah, let's" for "hey atlas" no longer reaches the router. If you say the phrase again in the 5 s after a command, earshot now hears it. Apple speech gets the phrase as a hint. The log counts near misses of the phrase, with no audio and no text (R-ON-1, R-ON-3, R-MD-1, D-11).
- The wake phrase spotter no longer loses a phrase that falls on its reset point. The spotter cleared its state every 1.5 s, also in the middle of a phrase. Now the reset waits up to 1 s while the phrase is open (R-ON-1, D-11).

## [0.1.0] - 2026-11-02

The first public release. earshot is early software. Expect bugs and changes to the settings format.

### Added

- Menu bar app with a management window, an Activity tab and a feedback note (R-ON-4, R-FB-1, R-MT-2).
- Speech on the Mac: Apple speech and Parakeet through transcribe.cpp. No audio leaves the Mac (R-SP-1, R-MD-1).
- Hold-key input and an always-on mode with a gate that ignores speech that is not for earshot (R-ON-1, R-ON-2, R-ON-4, R-ON-5).
- Command router with fixed verbs and targets read from the apps, not a script for each app (R-SP-2, R-MT-1, R-MT-2).
- Discovery of apps, sidebar names, search results and menu items through macOS accessibility.
- Actions: open an app, open a chat, focus the message box, type dictated text, click a named control, use window controls and menu items.
- "Show numbers", then "click N", for clickable items on the screen.
- Open a web address by voice (R-NV-7).
- Names matched by sound, so that a misheard name still finds the correct chat (R-NV-2, R-CL-1).
- Jev as an optional tier 2 of the router: off by default, text only, 1 s budget (R-MD-1, D-9).
- Optional click fallback: if a click finds no target, earshot can send one picture of the front window to Jev and click the item that Jev picks. It is off by default and a separate setting (R-MD-1, D-10).
- Open-source documents: license (MIT), contribution guide, code of conduct, security policy, third-party notices.

### Security

- earshot never presses Send, or does another action that cannot be undone, without an explicit command (R-NV-5, R-ON-5).

[Unreleased]: https://github.com/divyekant/earshot/compare/v0.2.0...develop
[0.2.0]: https://github.com/divyekant/earshot/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/divyekant/earshot/releases/tag/v0.1.0
