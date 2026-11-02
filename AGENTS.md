# Instructions for coding agents

## Read first

1. `docs/REQUIREMENTS.md` is the source of truth. Refer to requirement IDs (for example `R-SP-1`) in commits and tests.
2. `docs/DESIGN.md` is a proposal. If a measurement or a better option changes it, update the document in the same change.
3. `docs/DECISIONS.md` lists the rejected options. Do not propose them again without new evidence.

## Hard rules

- All audio and all decisions stay on the Mac. Do not add a cloud speech or LLM service (R-MD-1).
- Do not add a large-model agent loop to the command path (R-SP-2). The router must finish in about 300 ms or less.
- Do not write a script for each app. App support is data in the app table (R-MT-1, R-MT-2).
- earshot must never press Send or do another action that cannot be undone, unless the owner gives an explicit command (R-NV-5, R-ON-5).
- Measure latency for every change to the command path. Record the numbers in the pull request.

## Environment

- Mac Mini, Apple M4 Pro, 24 GB of memory, macOS 26.6.2.
- Local OpenAI-compatible MLX server (oMLX) at `http://localhost:11434/v1`. It is not Ollama. Do not use Ollama model names or endpoints.
- Homebrew is at `/opt/homebrew`.
- Swift: use Swift Package Manager.
- If a JS/TS tool is ever needed: use pnpm, not npm, and add `.npmrc` with `ignore-scripts=true`.
- If Python is needed (for example, Phase 0 measurement scripts): use `uv`, and commit `uv.lock`.

## Writing style

Write docs, comments and commit messages in Simplified Technical English:
- short sentences
- active voice
- one idea per sentence
- no marketing words

## Phase status

Phase 0 started with the E0 viability probe (`probe/`, `docs/experiments/E0-viability.md`). See `docs/DESIGN.md`, section 5.
