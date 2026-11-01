# Research: Voice Agents That Choose the App and Send the Message (macOS)

> Researched 2026-11-01 | about 30 sources consulted | 18 sources cited

## Executive Summary

No mature tool does "say one sentence, choose the app, send the message" fully on the Mac with open-source software. Some tools come close. Each one has a gap: it is cloud-only, it is in beta, it is not open source, or it needs large models.

The nearest options fall into three groups:

- **Commercial voice agents.** VoiceOS and mrmr target this exact use case for Slack and iMessage. Both are cloud services and are not open source [1][2].
- **Apple Siri AI.** It shipped as a public beta in macOS 27 on 2026-09-14. It sends Messages and Mail by voice. A third-party app works only if that app adopts the App Intents messaging schema [6][7][8].
- **Open source.** The open-source projects are early or experimental. The closest is Agent! [10]. It has voice input and Accessibility control, but it uses a noncommercial licence and recommends models that are too large for a 24 GB Mac.

Dictation tools do not choose the target app: Wispr Flow, Raycast, Superwhisper, VoiceInk and Handy. They only type into the field that has focus [4][5].

## Key Findings

### 1. Dictation tools do not route

Wispr Flow Command Mode only edits text or answers questions. It is a beta feature and needs a paid plan [4]. Raycast Dictation can press Enter after it pastes text ("Auto Submit"). You must first open the correct app and the correct conversation yourself [5].

Wispr Flow's roadmap names "voice to action" as Phase 2. In its Master Plan post (2026-03-03), the example tasks are "send a message" and "book a dinner". The post says the feature is "in its earliest days" and in prototype with power users. No demo, beta, or release was found as of 2026-11-01. The Wispr Flow MCP server is read-only: other agents can read Notetaker meeting data, but Wispr Flow cannot act in other apps [19][20].

**Confidence**: confirmed | **Sources**: [4], [5], [19], [20]

### 2. Commercial voice agents come closest

| Tool | Choose app + send from voice | Targets confirmed | Processing | Status |
|---|---|---|---|---|
| VoiceOS | Yes (claimed) | Slack, iMessage, Gmail | Cloud | Paid, 7-day trial [1] |
| mrmr | Yes, after you approve a plan | Slack, Gmail | Not stated | Invite-only beta [2] |
| Claude Cowork computer use | Yes, through connectors, then the screen | Slack (connector) | Cloud | Beta, Pro/Max/Ultra plans; voice only through separate dictation [3] |
| ChatGPT Voice (desktop) | Controls the computer by voice | Messaging not confirmed | Cloud | New, July 2026 [9] |

No source confirms a WhatsApp send from start to end in any of these tools.

**Confidence**: single-source for each tool (vendor pages) | **Sources**: [1], [2], [3], [9]

### 3. Apple Siri AI (macOS 27 public beta)

- Siri AI shipped on 2026-09-14 as a public beta. It is English only and needs an M1 Mac or later [6][8].
- It runs on the device and on Apple Private Cloud Compute (PCC). Features that run on servers have daily limits [6].
- It sends Messages and Mail by voice. A third-party messaging app must adopt the App Intents `.messages.sendMessage` schema [7].
- One report lists "send a WhatsApp message" as an action that is already available [6]. No first-party source confirms that the action works on a Mac.
- macOS 26 (Tahoe), which this Mac runs, does not have Siri AI. To get it, upgrade to macOS 27.

**Confidence**: confirmed (launch, schema); contested (WhatsApp on Mac) | **Sources**: [6], [7], [8]

### 4. macOS Voice Control

Voice Control runs on the Mac and is free. It operates the user interface step by step, for example "Open Mail" and "Click Send". It does not choose an app or a recipient from one sentence. Custom commands are possible but were not verified for a one-command send [11].

**Confidence**: confirmed | **Sources**: [11]

### 5. Open-source projects are early

| Project | Voice | Controls Mac apps | Local model | Licence | Status |
|---|---|---|---|---|---|
| Agent! (AgentiLoop) | Yes, on device | Yes (Accessibility, AppleScript) | Ollama, vLLM, LM Studio; recommends 30B+ | PolyForm Noncommercial | 652 stars [10] |
| voxagent | Yes (WhisperKit) | Through MCP tools | Yes | MIT | 5 commits, no release [12] |
| Jarvis (Swapnil-bo) | Yes (MLX Whisper) | Limited; WhatsApp through WhatsApp Web | Yes (3.8B) | None stated | Hobby project [13] |
| Agent S4 | No | Yes | Grounding model only | Apache-2.0 | Active, released 2026-10-20 [14] |
| UI-TARS Desktop | No | Yes (screenshots) | Yes (7B) | Apache-2.0 | Last news 2025-11 [15] |
| macOS-use | No | Yes | No | MIT | Archived 2026-09-25 [16] |
| Open Interpreter | No | Sandbox only | OpenAI-compatible | Apache-2.0 | Rewritten, no OS mode [17] |

**Confidence**: single-source (README claims) | **Sources**: [10]–[17]

### 6. Building blocks for a do-it-yourself setup

- A dictation app (VoiceInk or Wispr Flow) can type the request into an agent.
- MCP servers can send iMessages [18]. Slack has an official connector. The user already has both, so dictating into Claude works today.
- Accessibility-API control is reported to be more reliable than screenshot-based vision [10][Reddit LAVIE thread].

## Contradictions and Open Questions

- **WhatsApp through Siri AI on Mac.** One news report lists the WhatsApp action as available [6]. Another source says WhatsApp did not adopt the schema. A test on macOS 27 would settle this.
- **Confirmation step.** No source says whether a tool sends with no confirmation. mrmr and Claude ask for approval before they send.
- **Vendor bias.** Most commercial evidence comes from vendor pages, and the VoiceOS blog reviews its competitors. No independent Reddit or Hacker News reviews appeared.
- **Agent! on 24 GB.** It is not known how well Agent! works with an 8–14B model through oMLX. Agent! does not list MLX or a generic OpenAI-compatible endpoint.

## Methodology

Three parallel agents searched: (1) Apple built-in options, (2) commercial apps and AI assistants, and (3) open-source projects. Each agent ran 4–7 queries and used WebFetch to read official docs, GitHub READMEs, vendor pages and news sites. No second wave was run. The remaining gaps need hands-on tests, not more searches. Page summaries came from WebFetch and were not checked line by line.
