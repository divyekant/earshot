# E3. Jev sees the screen: the screenshot fallback for clicks

Date: 2026-11-02. Decision record: [D-10](../DECISIONS.md). Requirements: R-MD-1, R-CL-4, R-NV-5, R-SP-2.

## 1. Question

Can Jev find the target of a click on one picture of the front window, fast enough and safely, when the rules find no label?

## 2. Method

- The picture is the front window only (ScreenCaptureKit), as JPEG, longest side 1568 pixels or less. The API takes 280 to 1568 pixels on each side and does not resize.
- earshot draws the "show numbers" numbers on the picture (set-of-marks). Risky elements get no number.
- One request has two questions: a `choice` over the drawn numbers plus "none", and a `box` question. earshot uses the box only if Jev picks no number.
- For a box, earshot takes the middle point and checks the element under it (hit test, label, risky words, OCR text). The click path then checks the label again and blocks risky labels for the tier "jev".

## 3. Step 1: API check with synthetic images

The Remote Control session on the owner's Mac sent only synthetic images. It took no screenshot, clicked nothing and pressed no key.

- `GET /v1/models`: `jev-latest` and `jev-preview`. Both took images. Both answered as `jev-1.14.0`.
- Test image: 1440 x 900 PNG with 7 labelled items and an unlabelled "Quarterly report" card.

| Test | Calls | Right | Median latency | Input tokens |
|---|---|---|---|---|
| Choice, full-size PNG with numbers, 3 commands | 14 | 14 (p = 1.00) | 126 to 327 ms | about 3,900 |
| Choice, JPEG at half size (digits about 10 px) | 8 | 7 (read a 5 as a 3 once) | 227 ms | about 1,360 |
| Box, plain PNG, "the quarterly report card" | 10 | 10 (each edge within 0.012) | 155 to 181 ms | about 3,720 |
| Text only, same labels, no image (D-9 path) | 9 | 9 | 99 to 183 ms | about 430 |

- The first call and the slowest calls took up to about 1 s.
- Small numbers cause errors. So earshot draws the numbers on the final picture, with digits of about 13 px or more (`VisionMarks`).

## 4. Step 2: 20 real screens

Cases: [E3-cases.json](E3-cases.json). The harness `E3Screens` (in `app/Tests/EarshotAppTests`) opens a public page or an app, reads the screen, asks Jev, and reports what earshot would click. It never clicks and never presses a key.

The owner allowed only the 16 web and Calculator cases (no Finder, no System Settings), because the other pictures show personal data.

### 4.1 Run 1 (2026-11-02, branch b0ab098)

16 rows in 50 s. No click and no key press.

| Measure | Result |
|---|---|
| Cases that sent a picture | 10 of 16 |
| Jev answer right | 2 of 10 (wiki-search, gh-code) |
| Clicks that would be wrong | 3 (gh-star-risky: the forks link next to "Star"; gh-docs: a box on "2 months ago"; apple-bag: the browser address field) |
| Box with no element under the point | 4 |
| Jev stage, median / p90 | 350 ms / 543 ms |
| Total, median / p90 | 453 ms / 652 ms |
| Picture stage, median | 89 ms |
| First call (cold): picture, Jev, total | 184 ms, 376 ms, 585 ms |

Causes:
1. Calculator: the window is 230 x 408 points at scale 1. The API needs 280 pixels or more, so earshot took no picture.
2. 3 cases: a notification banner was the front app, so the test read the banner.
3. The box often marked no element, or a wrong element, on pages with many numbers.
4. Risky elements had no number. Jev then picked the element next to "Star".
5. The browser toolbar had numbers. Jev picked the address field for "the shopping bag".

Changes after run 1:
1. A small window is scaled up to the API minimum (`VisionRules.pictureSize`).
2. The harness skips a case if the expected app is not in front (`front` in the cases).
3. The box question is sent only if the picture has fewer than 3 numbers (`VisionRules.boxBelowMarks`).
4. Risky elements get a number. If Jev picks one, earshot refuses.
5. On a web page, only the page elements get numbers.

### 4.2 Run 2 (2026-11-02, branch 0260908)

All 16 cases sent a picture. No case was skipped. No click and no key press.

| Measure | Run 1 | Run 2 |
|---|---|---|
| Right | 2 of 10 with a picture | 8 of 16 |
| Clicks that would be wrong | 3 | 1 (hn-newest: the "Hacker News" home link; it can be undone) |
| Risky cases with no click | 0 of 2 tested | 2 of 2 (Jev answered "no target") |
| "No target" where a target exists (no click) | 4 | 7 |
| Calculator | 0 of 3 (no picture) | 3 of 3 |
| Jev stage, median / p90 | 350 / 543 ms | 293 / 428 ms |
| Total, median / p90 | 453 / 652 ms | 399 / 588 ms |
| Picture stage, median / p90 | 89 ms / — | 93 / 124 ms |
| First call (cold): picture, Jev, total | 184, 376, 585 ms | 179, 428, 617 ms |

- Without the first call: Jev median 288 ms, p90 340 ms; total median 396 ms, p90 453 ms.
- The harness counted hn-newest as right, because "Hacker News" contains "new". It now matches whole words.
- In the app, apple-bag and calc-seven do not reach Jev: the rules are sure (0.90) for them.
- The 7 misses are all "no target": Jev did not find "More", "Random article", the main menu, the docs folder, the bag, the logo and the search on apple.com. A miss does nothing.

### 4.3 Live clicks (2026-11-02, branch d9d34cd)

The owner said "go". The harness ran earshot's own click path on Jev's pick, with the tier "jev" (`EARSHOT_E3_CLICK=1`, [E3-live-clicks.json](E3-live-clicks.json)). 8 cases on Wikipedia, GitHub, Hacker News and Calculator. No other click and no key press.

| Measure | Result |
|---|---|
| Right picks | 7 of 8 (5 targets, and "no target" for the 2 risky commands) |
| Clicks that ran | 6, all ok; 5 changed the screen (Calculator "+" shows no change) |
| Wrong clicks | 1: "open the menu with the three lines" clicked "Help" (it can be undone) |
| Risky labels clicked | 0 of 2 (Star, HN submit) |
| Jev stage, median / p90 | 274 / 654 ms (first call 654 ms; others 169 to 439 ms) |
| Total, median / p90 | 374 / 844 ms |
| Click stage | 1 to 25 ms |

## 5. Decision

Merge the fallback as an opt-in setting, off by default.
- When it acted, it was right 8 of 9 times (run 2). The 1 wrong pick was a link that can be undone.
- It never picked a risky element. The click path blocks risky labels again for the tier "jev".
- It is fast enough: total p90 588 ms, below the 1.5 s budget.
- It finds the target only about half the time. So it is a fallback, not a main path.

Open: more real screens. The live test (4.3) clicked the right element 5 of 6 times. Try fewer numbers on large pages (only elements near the words of the command).
