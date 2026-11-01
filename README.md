# earshot

earshot is a local, always-on voice interface for macOS.

You look at the screen and say what you want. earshot finds the correct app, focuses the correct text box, types what you dictate, and clicks what you name. A small fast model makes each decision. earshot does not use a large AI agent for each step.

## Status

**Design phase.** The project contains no code yet.

- The requirements are in [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md).
- The proposed architecture and the phase plan are in [docs/DESIGN.md](docs/DESIGN.md).
- The options that were rejected, and the reasons, are in [docs/DECISIONS.md](docs/DECISIONS.md).
- The research that supports the design is in [docs/research/](docs/research/).

## Example commands

| You say | earshot does |
|---|---|
| "Slack Ravi, running late" | Opens Slack, opens the conversation with Ravi, focuses the message box, and types "running late". |
| "WhatsApp Mom" | Opens WhatsApp, opens the chat with Mom, and focuses the message box. You then dictate. |
| "Click Send" | Clicks the button with the label "Send" in the front window. |
| "Click the second email" | Clicks the second row of the email list. |
| "Show numbers", then "click 4" | Shows numbers on clickable items, then clicks item 4. |

## Target machine

- Mac Mini, Apple M4 Pro, 24 GB of memory
- macOS 26.3.1 (Tahoe)
- Local MLX model server (oMLX) at `http://localhost:11434/v1`, which is OpenAI-compatible

## Starting points

Read these before you write code:

1. [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md). This document is the source of truth.
2. [docs/DESIGN.md](docs/DESIGN.md), section "Phase 0". Do the measurements first.
3. [AGENTS.md](AGENTS.md). Rules for coding agents in this repository.
