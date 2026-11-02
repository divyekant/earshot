<p align="center">
  <img src="assets/brand/logo.svg" alt="earshot" width="320">
</p>

# earshot

earshot is a local voice interface for macOS.

You look at the screen and say what you want. earshot finds the correct app, focuses the correct text box, types what you dictate, and clicks what you name. Small, fast rules make each decision on your Mac. earshot does not use a large AI agent for each step.

> **CAUTION:** earshot types and clicks in other apps. It never presses Send, and it never does another action that you cannot undo, unless you say "send" (R-NV-5, R-ON-5). Read [Safety](#safety) before you use it.

## Status

earshot is early software. The first full build of the app is in progress. Expect bugs and changes to the settings format.

Each release has a tag `vX.Y.Z` and notes on the [Releases](https://github.com/divyekant/earshot/releases) page. [CHANGELOG.md](CHANGELOG.md) lists the changes. The `main` branch holds the latest release. The `develop` branch holds the work for the next release.

The experiments that showed that earshot is viable are in [docs/experiments/](docs/experiments/).

## What earshot does

| You say | earshot does |
|---|---|
| "Slack Ravi, running late" | Opens Slack, opens the conversation with Ravi, focuses the message box, and types "running late". |
| "WhatsApp Mom" | Opens WhatsApp, opens the chat with Mom, and focuses the message box. You then dictate. |
| "Open hn.com" | Opens the web address in your browser. |
| "Click Send" | Clicks the button with the label "Send" in the front window. |
| "Show numbers", then "click 4" | Shows numbers on clickable items, then clicks item 4. |

App support is data, not code. earshot reads the menus, sidebars and search results of your apps through macOS accessibility. It does not have a script for each app.

## Privacy

- All audio stays on your Mac. earshot saves no audio.
- All decisions stay on your Mac by default.
- One optional cloud model, Jev, can help when the rules are unsure. Jev is off by default. If you turn it on, earshot sends only text to Jev: the command words and the short list of labels on screen. It never sends audio, screenshots or message text. See [docs/DECISIONS.md](docs/DECISIONS.md), D-9.
- earshot keeps the Jev key in the macOS Keychain, not in a settings file.
- Settings, the app list and the name list are JSON files in `~/Library/Application Support/earshot`.

## Requirements

- A Mac with Apple silicon.
- macOS 26 (Tahoe) or later.
- Xcode 26 or later, or a Swift 6 toolchain with the macOS 26 SDK.
- A network connection for the first build. Swift Package Manager downloads transcribe.cpp (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).

## Build

1. Clone the repository:

   ```sh
   git clone https://github.com/divyekant/earshot.git
   cd earshot/app
   ```

2. Run the tests:

   ```sh
   swift test
   ```

3. Build the app bundle:

   ```sh
   scripts/build-app.sh
   ```

   The script writes `app/build/Earshot.app`.

If you have a code signing identity, the script uses it. If you do not have one, the script signs the app ad hoc. With an ad-hoc signature, macOS asks for the permissions again after each rebuild.

## Set up

1. Open `app/build/Earshot.app`. An ear icon shows in the menu bar. earshot has no Dock icon.
2. Click the ear icon, then click **Manage…**.
3. Open the **Permissions** tab. Give each permission:

   | Permission | Why earshot needs it |
   |---|---|
   | Accessibility | Read the screen, focus fields, type and click. |
   | Microphone | Hear commands. Audio stays on this Mac. |
   | Speech recognition | Use the Apple speech engine on this Mac. |
   | Input Monitoring | Read the hold key while another app is in front. |
   | Screen Recording (optional) | Read text that has no accessibility label, with on-device text recognition. |
   | Contacts (optional) | Find a chat by the name of a contact. This is off until you turn it on. |

4. Open the **Apps** tab. Click **Discover apps**. earshot reads the menus of your apps.
5. Select the apps that earshot may act in. Click **Approve**. earshot acts only in approved apps.
6. Open the **Names** tab. Make sure that the names of your chats are in the list. Add a name if it is missing.

## Use

1. Hold the right Option key.
2. Say a command, for example "Slack Ravi, running late".
3. Release the key.

earshot shows a small note with the result, for example "→ Slack · Ravi".

To change the hold key, open **Manage… > General**.

To try a command without your voice, open the **Test** tab. Type the command and click **Run**. By default, the Test tab shows the decision only. It acts only if you turn on **Also do the action**.

To see the time of each step of each command, open the **Activity** tab.

### Always-on mode

Always-on mode is off by default. In this mode, earshot listens all the time and decides if you speak to it. To turn it on, open **Manage… > General** and set **Mode** to **Always on**. earshot never presses Send or does a risky action from always-on mode. The hold key stays available.

### Speech engines

| Engine | Notes |
|---|---|
| Automatic (default) | Uses the Apple speech engine. |
| Apple | Apple speech on this Mac. |
| Parakeet | NVIDIA Parakeet through transcribe.cpp. earshot does not include the model file. Set the path to a Parakeet GGUF file in **Manage… > General**. If the path is empty, earshot uses the model file of the Hex app, if it is installed. |

### Jev (optional)

1. Open **Manage… > General**.
2. Paste your Jev key. earshot saves the key in the Keychain.
3. Turn on **Ask Jev** under **When the rules are unsure**.

earshot waits at most 1 s for Jev. After that, the rules answer wins.

## Safety

> **WARNING:** A Return key press in a message box sends the message. You cannot undo a sent message.

- earshot never presses Return or Send in a message box unless you say "send".
- earshot does not act on sign-in, code or payment pages.
- earshot acts only in the apps that you approve.

## Project layout

| Folder | Contents |
|---|---|
| `app/` | The macOS app (Swift Package Manager). One module for each part: speech, router, actions, discovery, input, UI. |
| `probe/` | The lab for the experiments E0, E1 and E2. |
| `docs/` | Requirements, design, decisions, build plan, experiments and research. |
| `assets/brand/` | The app icon and the logo. |

## Documents

- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) is the source of truth.
- [docs/DESIGN.md](docs/DESIGN.md) is the architecture.
- [docs/DECISIONS.md](docs/DECISIONS.md) lists the options that were rejected, and the reasons.
- [docs/BUILD-PLAN.md](docs/BUILD-PLAN.md) splits the build into tasks.
- [docs/research/](docs/research/) holds the research that supports the design.
- [docs/RELEASING.md](docs/RELEASING.md) gives the branches, the version numbers and the release procedure.
- [AGENTS.md](AGENTS.md) holds the rules for coding agents.

## Contribute

Read [CONTRIBUTING.md](CONTRIBUTING.md). All contributors must obey the [Code of Conduct](CODE_OF_CONDUCT.md).

To report a security problem, read [SECURITY.md](SECURITY.md). Do not open a public issue for it.

## License

earshot is released under the [MIT License](LICENSE). Third-party parts have their own licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
