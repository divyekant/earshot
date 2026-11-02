# Changelog

This file lists the changes in each release of earshot.

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). The version numbers follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). [docs/RELEASING.md](docs/RELEASING.md) gives the release procedure.

## [Unreleased]

### Added

- earshot runs on Intel Macs and on macOS 14 and 15. On these Macs, it uses Apple on-device dictation for speech. No audio leaves the Mac (R-MD-1).
- "Jev sees the screen" now works in the app: an unsure hold-key click that was not blocked can ask Jev with one picture of the front window. It is off by default (R-MD-1, R-NV-5, D-10).
- Always-on mode starts on a wake phrase (default "hey jarvis") and checks the owner's voice. Teach earshot your voice with 5 phrases in Manage > General. The models download one time (about 18 MB). No audio leaves the Mac (R-ON-1, R-ON-2, R-ON-3, R-MD-1, D-11).

### Changed

- Always-on mode no longer acts on speech with no wake phrase. The "for me?" text gate is removed (R-ON-1, R-ON-2, D-11).

### Fixed

- A tab or window title with a word such as "transfer" no longer blocks a switch to that tab. Bookmarks and History menu items are no longer click targets (R-NV-5, R-MT-1).

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

[Unreleased]: https://github.com/divyekant/earshot/compare/v0.1.0...develop
[0.1.0]: https://github.com/divyekant/earshot/releases/tag/v0.1.0
