# Contribute to earshot

Thank you for your interest in earshot. This file tells you how to report a problem, ask for a feature, and send a change.

All contributors must obey the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

Read these documents:

1. [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md). This document is the source of truth. Each requirement has an ID, for example `R-SP-1`.
2. [docs/DESIGN.md](docs/DESIGN.md). This document is the architecture.
3. [docs/DECISIONS.md](docs/DECISIONS.md). This document lists the options that were rejected. Do not propose them again without new evidence.

## Report a bug

1. Search the [issues](https://github.com/divyekant/earshot/issues) for the same bug.
2. If you do not find it, open a new issue with the **Bug report** form.
3. Include your macOS version, your Mac model, and the text of the **Activity** tab for the command.

> **CAUTION:** The Activity tab can show the names of your contacts and the text that you dictated. Remove private data before you paste it in an issue.

To report a security problem, read [SECURITY.md](SECURITY.md). Do not open a public issue for it.

## Ask for a feature

Open an issue with the **Feature request** form. Tell us the problem first, then your proposal.

## Rules for changes

These rules come from [AGENTS.md](AGENTS.md). A pull request that breaks one of them is not accepted.

- All audio stays on the Mac. Do not add a cloud speech service.
- Decisions stay on the Mac by default. The only cloud model is Jev: opt-in, off by default, text only, 1 s budget (R-MD-1, D-9).
- Do not add a large-model agent loop to the command path (R-SP-2). The router must finish in about 300 ms or less.
- Do not write a script for each app. App support is data (R-MT-1, R-MT-2).
- Do not add a verb or an intent for one app or one feature. Add a target source instead (`docs/DESIGN.md`, section 3.0).
- earshot must never press Send, or do another action that cannot be undone, without an explicit command from the owner (R-NV-5, R-ON-5).

## Send a change

1. Fork the repository and make a branch from `develop`.
2. Make your change. Keep each pull request to one topic.
3. If users can see the change, add one line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
4. Run the tests:

   ```sh
   cd app
   swift test
   ```

5. If your change touches the command path (speech, router, actions, discovery or input), measure the latency before and after the change. Use the **Activity** tab or the benchmark tests in `app/Tests`.
6. Open a pull request with `develop` as the base. Fill in the template. Include the latency numbers and the requirement IDs.

The workflow **CI** runs `swift build` and `swift test` on macOS for each pull request. The pull request can merge only when it passes.

Do not open a feature pull request to `main`. `main` gets only release pull requests from `develop`. [docs/RELEASING.md](docs/RELEASING.md) gives the branches, the version numbers, the tags and the release procedure.

### Tests that use the screen, keys or the microphone

Some tests act on the live Mac. They are skipped unless an environment variable turns them on, for example `EARSHOT_READ_BENCH=1`. Run them only when you do not use the Mac. They never type into a chat of another person.

## Writing style

Write docs, comments and commit messages in Simplified Technical English:

- Use short sentences.
- Use the active voice.
- Put one idea in each sentence.
- Do not use marketing words.

In a commit message, refer to the requirement IDs, for example `Router: match names by sound (R-NV-2)`.

## Code style

- Use Swift Package Manager. Do not add an Xcode project.
- Each module in `app/Sources` depends only on `EarshotCore`. Only `EarshotApp` depends on all modules.
- If a JS or TS tool is necessary, use pnpm and add `.npmrc` with `ignore-scripts=true`.
- If Python is necessary, use `uv` and commit `uv.lock`.

## License

When you send a contribution, you agree that it is released under the [MIT License](LICENSE).
