# E2: voice clicks on web pages, and Parakeet against Apple speech

Status: plan, 2026-11-02. The owner chose "Both (E2)".

E2 follows [E1](E1-generic-router.md). E0 and E1 put the cursor in a chat. The owner asked two more questions:

1. Can earshot act inside web pages ("click Sign in", "search for X", "open the second result")?
2. Can earshot use the Parakeet model that Hex already runs on this Mac?

## 1. Questions

1. **Read.** Can the probe read the visible links, buttons and fields of a Chrome page through Accessibility (AX), fast enough for each command (R-CL-1, R-MT-3)?
2. **Route.** From the spoken words and that element list, which router picks the correct element most often: local rules with fuzzy match, Jev, or rules first with Jev only when the rules are unsure? Does the router block risky elements every time (R-NV-5, R-ON-5)?
3. **Act.** How long from the text to the action (read, route, press), on live pages? Target: 300 ms or less, so that the total from the end of speech stays under 500 ms (R-SP-3).
4. **Speech.** On the same audio files, which engine gives text that routes correctly more often, and how fast: Apple SpeechTranscriber (used in E0) or Parakeet through transcribe.cpp with the model file of Hex?

## 2. Limits

- Audio and pages stay on the Mac. E2 sends no audio and no screenshot.
- Jev gets the command words and up to 8 element labels from the 4 public test pages. The probe replaces e-mail addresses in labels with "[email]" before it logs or sends a label. R-MD-1 does not change (see E1, section 2).
- One Jev call for each command at most. There is no agent loop (R-SP-2).
- E2 uses Chrome only. Other browsers can come later.
- The test pages are public pages: a Wikipedia article, the earshot repository on GitHub, a Google results page and the Hacker News front page. The list is data in `probe/e2-sites.json`. There is no script for each site (R-MT-1).
- Canvas pages (the body of Google Docs, Sheets, Figma) have no AX elements. E2 does not test them. OCR (R-CL-4) and "show numbers" (R-CL-3) come later.
- The owner gives no recordings. The audio comes from the macOS `say` command, with up to 3 English voices. This is a weak test of names in real speech. Section 6 says what this means for the decision.

### 2.1 Safety

> **WARNING:** A link on a web page can change data. On Hacker News, the "upvote" arrow is a link.

The probe obeys these rules:

1. It never presses an element whose label has a risky word: send, pay, buy, order, checkout, submit, delete, remove, publish, post, merge, close, archive, approve, accept, confirm, donate, subscribe, install, upload, share, report, block, vote, upvote, flag, hide, favorite, like, follow, star, fork, watch, sponsor, save, reply, comment, invite, cancel, sign out, log out, and similar. The router returns "blocked" for these.
2. In the live run, it presses links only. It does not press buttons, check boxes or menu items. The offline run tests the routing for those.
3. It never presses Return. It types only into a search field, through the field value, and then empties the field. It submits no form.
4. After each press, it goes back to the start page with the Back button of Chrome. If the start page does not come back in 4 s, the run stops.
5. It brings back the app that was in front when the run ends.

## 3. Method

### 3.1 Read the page

`earshot-probe e2-page` opens each site in Chrome as a new tab and reads it. It does not bring Chrome to the front unless `--front` is given. It sets `AXManualAccessibility` on Chrome, because Chrome builds its web tree only when an assistive app asks.

The probe asks Chrome for the visible elements with one call: `AXUIElementsForSearchPredicate` with the link and control search keys and "visible only". VoiceOver uses this call. If the call gives nothing, the probe walks the tree of the page and skips parts outside the window. It logs the time of each method.

For each element, the probe keeps the role, the label, the link address, the position, and if the link is in a heading. The label is the title, else the description, else the text inside the element. A field gives its placeholder. Elements with no label are counted, not kept. The snapshot stays on the Mac in `probe/logs/e2-page-<site>.json`. Git ignores it.

### 3.2 Test commands

`earshot-probe e2-make` makes the commands from the snapshots, with the correct answers. It uses only labels that occur once on the page.

| Kind | Example | What it tests |
| --- | --- | --- |
| exact | "click Pull requests" | The full label |
| free | "take me to Pull requests", "can you open the Talk link" | Other command words, role words |
| partial | "open conduct" for "Code of conduct" | Part of a long label |
| misheard | "click Pull riquests" | One wrong vowel |
| ordinal | "open the second result" | Position (R-CL-2) |
| search | "search for local voice control" | Type into the search field, no Return |
| risky | "click Star" | The router must block it |
| unknown | "click pricing plans" on a page with no such label | Answer: none |
| scroll, back | "scroll down", "go to the top", "go back" | Page actions |
| none | "I think the meeting moved to Thursday" | Not a command |

"Result" means a link in a heading (Google and Wikipedia search results). If a page has fewer than 2 of these, it means a link with 4 or more words (Hacker News stories). The ordinal answers use the same definition, so the offline run checks only the parse. The live run prints the label of each pressed result, to check it by eye.

### 3.3 Router

The router is generic. It knows no site.

1. Parse the words: back, scroll, search (type), ordinal, or press.
2. For press: take the words after the command word. Remove "the", "button", "link" and similar words at the edges.
3. Score each element: the larger of (a) the similarity of the whole phrase to the label and (b) the share of spoken words found in the label, reduced a little for long labels.
4. The rules are sure if a command word is present, the best score is 0.8 or more, and the next different label scores at least 0.08 less. A score under 0.5 gives "none".
5. If the rules are unsure, Jev picks from the top 8 elements plus "scroll down", "go back" and "none".
6. The risky-word check runs on every answer, also on the answer of Jev.

### 3.4 Live run

`earshot-probe e2-act` brings Chrome to the front, opens each site, and runs the commands for that site: read, route, act, go back. It logs the time of each step. The owner stays off the Mac for about 5 minutes.

### 3.5 Speech

1. `earshot-probe e2-say` makes WAV files (16 kHz, mono) from the E1 test commands with `say`, with up to 3 English voices (Indian English first). The files stay in `probe/logs/e2-audio/`. Git ignores them.
2. `earshot-probe e2-asr` transcribes each file with Apple SpeechTranscriber, without hints and with the chat names as hints (as in E0).
3. `probe/parakeet` is a separate small Swift package. It loads Hex's model file (`parakeet-unified-en-0.6b-Q8_0.gguf`, read only) through transcribe.cpp 0.3.1 (MIT, prebuilt for Apple) and transcribes the same files. It keeps the earshot probe free of other code.
4. `earshot-probe e2-asr-score` compares the engines: word errors, and if the E1 rules route the text to the correct chat. The route result is the main measure, because a wrong name opens a wrong chat.

## 4. Pass marks

| Measure | Pass |
| --- | --- |
| Read time, visible elements | 150 ms median or less |
| Hybrid router, correct | 90 % or more |
| Risky elements pressed | 0 |
| Live, text to action | 300 ms median or less |
| Speech | Parakeet becomes the default only if it routes more commands correctly than Apple, and is at most 100 ms slower |

## 5. Results

Not run yet.

## 6. Decision

Not made yet.
