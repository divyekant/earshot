# E2: voice clicks on web pages, and Parakeet against Apple speech

Status: running, 2026-11-02. The owner chose "Both (E2)". The press test (section 5.6) found the cause of the failed presses. Live run 3 waits for the owner.

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
6. A real mouse click occurs only on a link that does not offer `AXPress`, only while Chrome is in front, and only at a point where the top element on screen (over all apps) is that link or a part of it. The pointer goes back after the click. `e2-press` clicks only with `--mouse`.

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

The probe ran on the owner's Mac from the remote session on 2026-11-02. Chrome was signed in. The probe replaced the owner's e-mail address in a Google label with "[email]" before it logged or sent the label.

### 5.1 Read

`e2-page`, pages in background tabs, median of 3 reads:

| Site | Elements | Links | Buttons | Fields | No label | Read | Tree walk |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Wikipedia | 99 | 80 | 10 | 1 | 0 | 36 ms | 119 ms |
| GitHub | 76 | 57 | 17 | 1 | 0 | 31 ms | 33 ms |
| Google | 32 | 17 | 14 | 1 | 0 | 26 ms | 31 ms |
| Hacker News | 191 | 191 | 0 | 0 | 30 | 47 ms | 95 ms |

- The one-call search (`AXUIElementsForSearchPredicate`) worked on all pages. It was 1 to 3 times faster than the tree walk. The time to find the page in the window was 20 to 22 ms of each read.
- The check for links in headings adds 15 to 40 ms. Only an ordinal command needs it.
- The 30 elements with no label on Hacker News are the vote arrows. The reader does not keep elements with no label, so the router cannot press them.

### 5.2 Route (saved pages)

`e2-run`, 45 commands, after the fixes in commits 75892a2 and 810095f:

| Router | Correct | Wrong press | Median | Slowest 1 in 10 |
| --- | --- | --- | --- | --- |
| Rules + fuzzy (Mac) | 42/45 (93 %) | 0 | 23 ms | 56 ms |
| Jev for press commands | 44/45 (98 %) | 1 | 106 ms | 168 ms |
| Rules, Jev if unsure | 45/45 (100 %) | 0 | 24 ms | 64 ms |

- The rules were sure for 42 of 45 commands, and right for all 42.
- The rules were unsure only for free phrasings with no command word ("tools please", "I want to see accessibility"). Jev got all 3 right.
- All 4 risky commands ("click Donate", "click Star", "click Share", "click submit") gave "blocked".
- Jev alone pressed "Packages" for "click pricing plans", also with a stronger "none" option. The hybrid did not, because the rules were sure that nothing matched. So Jev must not get a command that the rules can answer with "none".
- The first run found one bad test: Wikipedia's fundraising banner was a "result". Ordinal lists now leave out risky links, and only pages with a result list get an ordinal test.

### 5.3 Live run 1

`e2-act`, 42 commands on the 4 live pages (commit 75892a2):

- The router picked the correct element for 40 of 42 commands. The 2 misses were test drift: a Hacker News story that was gone, and a label that changed from "(+2)" to "(+1)".
- From the text to the action: 47 ms median, 77 ms for the slowest 1 in 10, with Jev for 2 commands. Page read: 29 ms median.
- But Chrome ignored the presses. 21 of 22 link presses changed nothing, and both value sets in search fields failed. The press call returned at once with no error.
- Cause: the probe took the first web area in the window. Chrome keeps the pages of other tabs in the tree, with the same size. Each command step had opened a new tab, so the probe read and pressed a hidden tab. One press on a Hacker News link was followed by a Google address, which showed this.
- Fix (commits 810095f and c43dfa8): a hit test in the Chrome window finds the page that is on screen. The live run acts only on a page found this way. Else it brings Chrome to the front, and if the page is still not on screen, it stops.
- Safety held: nothing was submitted, no Return was pressed, and all 4 risky commands were blocked.

### 5.4 Speech

126 files: the 42 E1 commands, spoken by `say` with the voices Rishi (Indian English), Samantha (US) and Daniel (UK). The route is the E1 rules on the text, on the Mac, with no Jev. With the written words, the rules route 120 of 126 correctly.

| Engine | Word errors | Route correct | Wrong chat | Median | Slowest 1 in 10 |
| --- | --- | --- | --- | --- | --- |
| Apple SpeechTranscriber | 18.8 % | 113/126 | 4 | 56 ms | 65 ms |
| Apple SpeechTranscriber, name hints | 18.8 % | 113/126 | 4 | 55 ms | 65 ms |
| Apple DictationTranscriber | 16.5 % | 102/126 | 5 | 88 ms | 157 ms |
| Apple DictationTranscriber, name hints | 14.8 % | 101/126 | 5 | 131 ms | 183 ms |
| Parakeet (Hex's file, transcribe.cpp, Metal) | 14.9 % | 114/126 | 4 | 34 ms | 40 ms |

- SpeechTranscriber ignores the name hints: the text is the same, line for line. DictationTranscriber uses them, but it changes the command words more ("Slag me", "Open claw"), so it routes worse.
- Parakeet loads in 14.4 s the first time and uses about 890 MB after the load. It must stay loaded.
- Both engines miss the same names: "Udita" gives "a ditty", "Mrunal" gives "Marinel" or "Manal", "Claude" gives "clawed" or "cloud". The word "ping" at the start is sometimes lost.
- `say` voices are not real speech. The names are the hard part, and these results show the same weak names for both engines.
- The macOS sandbox of the remote session blocked SwiftPM downloads and the run of a downloaded library. The owner ran `parakeet-ab` once in the terminal.

### 5.5 Live run 2

`e2-act`, 42 commands on the 4 live pages (commit 545fe11, with the hit test of commit c43dfa8):

| Measure | Result |
| --- | --- |
| Page found by the hit test | 4 of 4 sites |
| Read the page | 12 ms median, 21 ms for the slowest 1 in 10 |
| Correct element or answer | 39 of 42 |
| Text to action (read, route, Jev if unsure, act) | 29 ms median, 51 ms for the slowest 1 in 10 (26 actions) |
| Link pressed, page changed | 0 of 22 |
| Typed into a search field | 2 of 2 (key events; the field was emptied after) |
| Scrolled | 2 of 2 |
| Risky items blocked | 4 of 4 |

- The hit test fixed the tab problem. The read is also faster: 12 ms against 29 ms in live run 1.
- The press call (`AXPress`) still returned success at once, and Chrome still did not follow the link. This time the link was on the visible tab. So the hidden tab of live run 1 was not the only cause.
- Setting the value of a search field failed again. The fallback with key events worked, because the probe first put the focus in the field.
- 2 misses were test drift: a Google result and a Hacker News story were gone from the live page. The router said "none" for both, and "none" is the correct answer for a label that is not on the page. `e2-act` now scores these commands this way.
- 1 miss was a Jev call that took 5 s and then failed ("nvidia build please"). `e2-act` now gives Jev 1 s at most, and then keeps the rules answer. Jev took 106 ms (median) in `e2-run`.
- Safety held: nothing was submitted, no Return was pressed, and no dialog, sign-in page or form page appeared.

### 5.6 Press test

`e2-press` opens the Wikipedia page, picks one plain link to another article, and tries each way once. After each page change, it goes back.

| Way | What it does |
| --- | --- |
| press | `AXPress` on the link, as in live runs 1 and 2 |
| focus, then press | Set `AXFocused` on the link, then `AXPress` |
| press the text inside | `AXPress` on the first child of the link |
| enhanced UI, then press | Set `AXEnhancedUserInterface` on Chrome, as VoiceOver does, then `AXPress`. The probe sets the old value again after. |
| open the address | Open the address of the link (`AXURL`) in Chrome. This makes a new tab. |
| mouse click (`--mouse` only) | A real click at the link, after a hit test shows that the point is on the link. The pointer goes back after. |

Result (commit 743fc8f), on the link "Talk" of the Wikipedia page:

| Way | Page changed | Call | Press to new page |
| --- | --- | --- | --- |
| press | No | 0.1 ms | |
| focus, then press | No | 24 ms | |
| press the text inside | No | 0.2 ms | |
| enhanced UI, then press | No | 0.2 ms | |
| open the address | Yes, in a new tab | 0.3 ms | 79 ms |
| mouse click | Yes, in the same tab | 17 ms | 85 ms |

- Cause: a Chrome link does not offer `AXPress`. Its actions are `AXShowMenu` and `AXScrollToVisible` only. Chrome still returns success for `AXPress`, and does nothing. This explains all 43 silent presses of live runs 1 and 2.
- Focus, the text inside the link, and `AXEnhancedUserInterface` do not change this.
- The hit test at a link gives the deepest element, for example the text or a group inside the link. A check that the point is on the link must go up the parents.
- Nothing was submitted, and no Return was pressed.

Rule for earshot (commit after 743fc8f, `WebPage.press`):

1. If the element offers `AXPress`, use it.
2. Else, if the browser is in front, find a point where the top element on screen is the element or a part of it. Click there, and move the pointer back.
3. Else, do not press. Say why.

"Open the address" stays an option for a command such as "open X in a new tab".

### 5.7 Live run 3

`e2-act` with the rule of section 5.6, on the 4 live pages. Not run yet.

## 6. Decision

Not made yet.
