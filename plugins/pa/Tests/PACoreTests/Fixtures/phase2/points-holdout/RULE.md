# The rule for the marks

Each document has 3 marked sentences in `marks.tsv`. The rule is:

"The 3 sentences that the owner must know to act on this document: what is asked or decided, how much, and by when."

- One mark says what the owner must do, or what was decided.
- One mark says the amount (money, or a number with a unit).
- One mark says the date or the deadline.
- If one sentence holds two of these, the third mark is the next most necessary sentence for the action.
- Each mark is one full sentence of the document, character for character, as the sentence splitter of the PA cuts it.

All documents, names, companies, addresses and numbers are made-up. This folder is the holdout of the main points follow-up (R2). Do not tune on it. It was written and committed before the code of main points version 2.
