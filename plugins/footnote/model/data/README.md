# Fit data of E13, package M1 (a quarter of build spec 5.2)

All items and pairs are made-up. Each was written by hand by a writer session (no generator, build spec 2 rule 4) and labeled by a different session with the rule files `RULE-need.md`, `RULE-when.md`, `RULE-pair.md` of the design thread. The briefs are in `../m1/`.

| File | Rows | Writers | Owners | Use |
|---|---|---|---|---|
| `items-fit` | 1,598 | 6 | 24 | fit (D1, D4) |
| `items-dev` | 401 | 6 | 6 (1 per writer) | select thresholds |
| `fit-train` | 1,487 | 2 | 12 | fit (D2) |
| `fit-dev` | 484 | 2 | 4 (2 per writer) | select thresholds |
| `close-train` | 736 | 1 | 6 | fit (D3) |
| `close-dev` | 264 | 1 | 2 | select thresholds |

- An item or a pair stays only if the label of the labeler is equal to the intent label of the writer (`m1/assemble.py`). Dropped: 11 of 2,010 items, 29 of 2,000 fit pairs, 0 of 1,000 close pairs.
- The dev owners are not in the fit files.
- Addresses on other domains were changed to a subdomain of `example.org` or `example.net`.
