# Decisions

This log records the options that the owner and Claude examined on 2026-11-01, and the decision for each one.

## D-1. A dictation app alone is not enough

| Option | Result | Reason |
|---|---|---|
| macOS Dictation | Rejected | Only dictation. Less accurate. No routing. |
| Handy (MIT) | Not enough | Local and light, but only dictation. |
| VoiceInk (GPLv3) | Not enough | Local Whisper, AI cleanup through oMLX, per-app styles ("Power Mode"). Types only into the focused field. |
| Wispr Flow | In use now; not enough | Cloud processing. About 1.4 GB of memory. The free plan has a weekly word limit. Its "voice to action" feature is only on the roadmap (Master Plan post, 2026-03-03) and has not shipped. Its MCP server is read-only. |

**Decision:** Keep Wispr Flow or VoiceInk for plain dictation. Build earshot for routing, focus and clicks.

## D-2. Do not use large-model agents for each step

| Option | Result | Reason |
|---|---|---|
| Claude (desktop or computer use) | Rejected | 1–5 s for each model call. Navigation needs 3–4 steps, so 5–20 s in total. |
| OpenClaw, Hermes Agent | Rejected | Same agent loop and same latency. These agents work mainly through tools and APIs, not fast navigation of the user interface. |
| ChatGPT Voice desktop, VoiceOS, mrmr | Rejected | Cloud, not open source, or invite-only. |

**Decision:** Use a "System 1" design. Small fast models choose from a limited set of actions. No model plans steps.

## D-3. Do not use fixed scripts for each app

A Hammerspoon script with one recipe for each app was proposed first. The owner rejected it, because each new app and each app update needs script changes.

**Decision:** Use one data table with one row for each app, and generic accessibility logic (DESIGN.md, section 5).

## D-4. Siri AI is not the base

Siri AI shipped as a public beta in macOS 27 on 2026-09-14. It needs macOS 27, and this Mac runs macOS 26.3.1. A third-party app works only if it adopts the App Intents messaging schema. WhatsApp support on the Mac is not confirmed. Siri AI is also not open and does not do generic clicks.

**Decision:** Do not depend on Siri AI. Check it again when the owner upgrades to macOS 27.

## D-5. Small models, all local

The owner sees the screen and gives exact commands. The system matches the command to a small set of choices. It does not need to reason.

**Decision:** Use models of 0.6B parameters or fewer for speech and routing. Use no model for label matching (string similarity). Use the oMLX server only for optional text cleanup.

## D-6. Native Swift app (proposed)

The best components for the Mac are Swift libraries:
- AXorcist and Peekaboo for accessibility
- FluidAudio and speech-swift for VAD, speech to text, turn detection and speaker embeddings
- Apple Vision for OCR

A native menu-bar app also uses less memory than Electron.

**Decision:** Build earshot as a Swift menu-bar app. A Hammerspoon or Python prototype is acceptable for Phase 0 measurements only. Change this decision if Phase 0 shows a better option.

## D-7. Do not use computer-use agents or Cua Driver

The owner asked about "CUA" on 2026-11-02. The facts below come from the trycua/cua README and the cua.ai documentation. Nobody ran Cua Driver on this Mac.

| Option | Result | Reason |
|---|---|---|
| Computer-use agent (CUA) loop, for example Claude computer use or the OpenAI CUA model | Rejected | This is the agent loop of D-2. A large model reads a screenshot and selects one action for each step. Each step takes 1–5 s. |
| trycua/cua: Lume, Cua Spaces, SDKs, Cua Bench | Rejected | These parts run agents in virtual machines, or they test agents. earshot must operate the real desktop of the owner. |
| Cua Driver (MIT, pre-release) | Rejected | See the list below. |
| CUA-S1 models (trycua) | Not needed now | These are small "System 1" models. The first model only makes decisions about form fields. It does not select a chat or a text box. |

Cua Driver is the only part of trycua/cua that operates the real Mac. These are the reasons not to use it:

- It uses the same Accessibility API as earshot, through one more process. It does not make earshot faster. The project publishes no latency numbers.
- By default, it does not raise the window or change the frontmost app. Its foreground mode does one action and then restores the previous app. earshot must leave the owner in the chat, with the cursor in the text box (R-NV-3).
- Its main interface is an MCP server (R-MD-6). It has no Swift bindings.
- Its setup needs an install script, a background service, and two permissions: Accessibility and Screen Recording.
- If a model controls it, the model can press Return. Return sends the message in Slack, WhatsApp and Messages (R-NV-5).

**Decision:** Keep the direct Accessibility approach (DESIGN.md, section 3.5). The E0 probe uses it, and it reached the Slack text box in a median of 466 ms (docs/experiments/E0-viability.md). Cua Driver reads the accessibility state again after each action to make sure that the change occurred. E0 already does a similar check: it types text only when the chat name on the screen is correct. Keep this check in the final design.
