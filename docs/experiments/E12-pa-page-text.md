# E12: the text of kept web pages for the PA plugin

Status: closed on 2026-11-12. The page read and the main text rule pass each go mark on the sealed holdout, in Chrome and in Safari. Main points of a web page fail their mark (6 of 10 against 8 of 10). The setting `pagePoints` is `false` by default. On the Mac, the memory of the PA (24.9 MB) failed its mark of 15 MB.

Source: the PA phase 4 build spec, sections 6 to 11 (`/mnt/project-files/earshot-pa/phase4-build-spec.md` in the project folder). Requirements: R-PA-4, R-PA-9, R-PA-13, R-PL-2, R-PL-5. Decision: D-18.

All pages in this experiment are made up. Each page was written one by one, with no generator and no templates.

## Question

1. Can earshot read the main text of the web page in front through Accessibility, fast, with no change to the page?
2. Can a fixed rule select the main text from the blocks of the read, so that "where is" finds the page with a question in other words?
3. Does the main points rule of the PA (version 2, made for kept documents) select the key sentences of a web page?

## The read (probes W1)

The bench is `app/Tests/EarshotActionsTests/PageReadBench.swift`. It ran on the Mac Mini (macOS 26.6.2) on 2026-11-12 at about 05:30 UTC. The default browser was Chrome. The second browser was Safari.

Two methods were compared:

- **Method A**, the tree walk: a block for each heading, text group, list item and cell, with the zone from the landmark subrole and the link share.
- **Method B**, the text range of the main landmark.

Share of the label words that the read found:

| Page | Chrome A | Chrome B | Safari A | Safari B |
|---|---|---|---|---|
| news | 1.000 (12 ms) | 0.987 | 1.000 (11 ms) | 1.000 |
| blog (div only) | 1.000 (23 ms) | 0.989 | 1.000 (11 ms) | 1.000 |
| docs | 1.000 (17 ms) | 0.899 | 1.000 (14 ms) | 1.000 |
| cookie dialog | 1.000 (10 ms) | 0.964 | 1.000 (7 ms) | 1.000 |
| editor (text area) | 1.000 (3 ms) | 0.993 | 1.000 (4 ms) | 0.007 |
| long (5,024 words) | 1.000 (108 ms) | 0.994 | 1.000 (16 ms) | 1.000 |

- Method A passes P1 in the default browser. Method B fails (docs 0.899 in Chrome, editor 0.007 in Safari), and B gives the values of one-line fields. **Selected: method A.** A has zones and link shares. B has neither.
- P2, the first read: complete in Chrome and Safari. The browsers already ran, so a cold start was not tested.
- P3, no change: scroll, selection and focus did not change in 4 of 4 runs. One more Accessibility call during a read took 0.5 ms or less.
- P4, a page that loads: Safari gave `complete: false` at 20,000 elements after 1,693 ms. Chrome showed no web area within 8 s for the 40,000-row page. Not measured in Chrome.
- P5, protected pages: no blocks for the sign-in page, and no one-line field value, in the two browsers. Pass with method A.
- P6, other content: a PDF in Chrome reads with A (1.000). A PDF in Safari has no web area. A frame reads with A in the two browsers. An Electron app (Slack) gave 112 blocks in 91 ms with A.

A second fix came from the development read: Chrome sometimes builds its tree late. earshot reads again (after 1 s, for 3 s at most) if a read gives fewer than 50 words (#172). The page text reader (`PageTextReader`, through `ScreenReader.visibleWebArea`) writes no attribute.

Correction of 2026-11-12 (PA phase 5): an earlier version of this paragraph said that earshot sets `AXManualAccessibility` for the page read. That was wrong. Chrome 157.0.8103.52 does not support `AXManualAccessibility`: a read and a set give -25205. The clean probe 7 of phase 5 (a new Chrome with an empty profile, in front, screen not locked) gave a web area after 1 s, with no flag and with `--force-renderer-accessibility`. The first run of probe 7 had no web area because its window was not in front and the screen was probably locked. A try to set `AXEnhancedUserInterface` on the probe Chrome in that first run was refused (-25208). earshot does not set `AXEnhancedUserInterface`.

## The main text rule

The rule is `MainText.select` in `plugins/pa/Sources/PACore/Web/MainText.swift`. All numbers and word lists are in that file.

1. Use the main zone if it has 150 words or more, without nav, aside, form, search, footer and dialog blocks.
2. If not, use all blocks without nav, banner, footer, aside, search, form and dialog blocks.
3. Drop a block if more than half of its characters are link text (not a heading). Drop a block of fewer than 4 words (not a heading, list item or cell). Keep a short block between two kept blocks. Keep a heading only if a kept block follows it. Drop a block of 4 words or more if an earlier kept block has the same words.
4. After an end word ("Comments", "Related", "You may also like", and others), drop the blocks up to the next heading of the same or a higher level.
5. If fewer than 50 words stay, the page has no text.

Variants: (a) the full rule, (b) steps 1, 2 and 5 only, (c) all blocks. A second switch puts the page heading in front of each passage.

## Development (pages-dev, 30 pages, 60 questions)

The blocks of the 30 pages come from the real read in Chrome (`pages-dev/blocks/`). The store also had the 40 documents of the phase 2 corpus. Search model: EmbeddingGemma-300M (Q8_0).

| Variant | Found ≥ 0.90 | Noise ≤ 0.25 | Median noise | Search (first 3) |
|---|---|---|---|---|
| a | 30 of 30 | 29 of 30 | 0.051 | 60 of 60 |
| b | 30 of 30 | 26 of 30 | 0.128 | 60 of 60 |
| c | 30 of 30 | 25 of 30 | 0.165 | 60 of 60 |

The search number was 60 of 60 for each variant, with and without the heading in front. The tie rule selected the lowest noise: **variant a, heading in front off**. The ceiling (main lines of the labels) was also 60 of 60.

Main points on `points-dev.tsv`: 10 of 10 pages with 2 or more of the 3 marked sentences.

## Holdout (pages-holdout, 24 pages, 48 questions), one run for each browser

The holdout was sealed until this run. Nobody opened its pages, labels or questions before the run. No number was changed after the run.

| Mark | Chrome (default) | Safari | Pass |
|---|---|---|---|
| Found ≥ 0.90 | 24 of 24 | 24 of 24 | 21 or more of 24 |
| Noise ≤ 0.25 | 24 of 24 (median 0.131) | 24 of 24 (median 0.141) | 20 or more of 24 |
| Search, correct page in the first 3 | 45 of 48 (other words 21 of 24) | 45 of 48 (other words 21 of 24) | 43 or more of 48 |
| Ceiling (label main lines) | 46 of 48 | 46 of 48 | no mark |
| Main points, 2 or more of 3 | 6 of 10 | 6 of 10 | 8 or more of 10 |
| Pages with no text | 0 | 0 | |

- The read was complete on each of the 24 pages in the two browsers. The read took 5 to 20 ms in Chrome and 7 to 27 ms in Safari. With the wait for a stable tree, the full time was 1.1 to 1.5 s in Chrome and 1.2 to 2.3 s in Safari.
- Safari gave fewer blocks on two pages (w18: 5 against 10; w22: 16 against 34). The search and the main points numbers did not change.
- Each of the 24 kinds of page (news, forum, recipe, webmail, terms, and others) passed found and noise.

Main points for each marked page (marked sentences in the 5 selected, the same in the two browsers):

| Page | w02 | w06 | w07 | w10 | w14 | w16 | w17 | w18 | w20 | w22 |
|---|---|---|---|---|---|---|---|---|---|---|
| Marked in the 5 | 0 | 2 | 1 | 2 | 3 | 3 | 3 | 2 | 1 | 1 |

## Result

- **The page read and the main text rule pass.** "keep this" on a web page keeps the main text with variant a.
- **Main points of a web page fail** (6 of 10). As the spec says, `pagePoints` is `false` by default. "main points" for a web page answers "Main points work for kept files only." There is no third version of the rule. Main points for kept documents do not change.
- The development set gave 10 of 10 and the holdout gave 6 of 10. The development pages were too close to the rule. The rule looks for amounts, dates and requests, and a web article often has its main statement in a sentence with none of these.

## Limits

- English pages only. Made-up pages only, read from `file:` addresses.
- Two browsers (Chrome and Safari) on one Mac. Firefox and other browsers are not tested.
- The page must be in front and loaded. Text that the page did not load is not kept. A page that loads for a long time can give `complete: false`.
- A cold start of the browser was not tested.
- The page must be in the front window, and the screen must not be locked. Probe 7 failed 3 times with "no web area within 15 s" (last on 5998e2d): its window was not in front, and the screen was probably locked. The clean probe of phase 5 (probe 8, 2026-11-12) brought a new Chrome with an empty profile to the front with the screen not locked: the web area was there after 1 s, with no flag and with `--force-renderer-accessibility`. If earshot cannot read the page, it sends an error, and the PA keeps the link with no text.

## Final check on the Mac (2026-11-12, 07:04 to 07:16 UTC)

earshot 0.5.0 (5998e2d), PA 0.4.0, the owner's real store. Made-up `file:` pages in a new Chrome window. The network of the Mac stayed on, because the remote session needs it. In its place, the check counted the network connections of the PA and of its worker during each keep and search.

| Mark | Number | Result |
|---|---|---|
| Keep a made-up page | "Kept"; 2 passages; read and index in 62 ms or less; `keepThis` 4 to 9 ms | Pass |
| No network | 0 connections of the PA and the worker during each keep and search | Pass |
| Find it in other words | Position 1 for 4 of 5 questions. "the money for a vegetable bed" did not find it (the page says "renewal fee" and "plot") | Pass (4 of 5) |
| earshot speed ("open safari", 20 runs) | Route median 7.9 ms with no read; 5.8 ms (slowest 7.6) with 20 page reads during the runs | Pass |
| Memory, PA with no worker | 24.9 MB (23.2 MB before the keep). The worker uses 330 to 420 MB while it runs and stops 5 minutes after the last search | **Fail** (mark: less than 15 MB) |
| Drop | 42 test pages dropped; 0 left; their passages deleted | Pass |

The memory mark failed on the owner's real store. The bench store gave 6.3 MB. A keep added about 1 MB. The time to the note "Text kept" is short (the read and the index took less than 0.1 s after the read of earshot), but the check did not record it from the command to the note.
