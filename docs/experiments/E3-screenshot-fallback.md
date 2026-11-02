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

Results: to be added.

## 5. Decision

To be added after step 2.
