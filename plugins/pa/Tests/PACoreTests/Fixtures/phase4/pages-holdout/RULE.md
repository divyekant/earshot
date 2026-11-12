# Phase 4 sealed holdout: web pages

Written by the thread "Design the Earshot PA plugin" on 2026-11-12, for `phase4-build-spec.md`, sections 7, 8.1 and 10.

**Sealed.** The build thread does not open `pages/`, `labels/`, `questions.tsv` or `points.tsv`. Its bench reads them and prints counts. Copy this folder to the fixture folder in a first commit, before the code of W3. One run for each browser. After the run, the files are seen and become development data.

All content is made-up: the people, the companies, the places, the addresses and the numbers. I wrote each page one by one. A script only removed my label marks from the HTML, put the pages in a random order and wrote the label files. The pages have no script and load nothing from the network.

## Files

| File | Content |
|---|---|
| `pages/w01.html` to `w24.html` | 24 pages. Open each one in the browser from its `file:` address and read it through the real page read. |
| `labels/w01.tsv` to `w24.tsv` | For each page: lines of `class<TAB>text`. The class is `main` or `neutral`. Text that is in no line is noise. |
| `labels/pages.tsv` | For each page: its kind, if it has landmark elements (`landmarks`, `roles`, `partial`, `none`), and the counts of main, neutral, noise and hidden words. Use it for the numbers by kind of page. |
| `questions.tsv` | 48 questions, 2 for each page: `id`, `page`, `other_words`, `question`. The question is the words after the lead "where is". `other_words` is 1 if the question uses other words than the page for its main things (24 of 48). |
| `points.tsv` | 10 pages with 3 marked sentences each: `page`, `sentence`. Each sentence is in one `main` line of its page, character for character. |

## The label rule

- **main**: the text that a person opens the page to read. The title of the page content. The body: paragraphs, headings, lists, tables and code of the body. In a forum thread or a question page: the question and the answers. In a mail: the subject and the text of the mail. In a note of a web editor: the text of the note.
- **neutral**: the line with the author and the date, a caption, a table of contents of the body, a list of references, an info box, "last updated", keywords, a footnote and its mark, a pull quote that repeats a sentence of the body, the reviews below a product, a signature below a forum post, the short comments below a question or an answer. These lines count for nothing.
- **noise**: all other text. Navigation, menus, the page header and footer, a sidebar, links to other articles, advertisements, a cookie notice, a newsletter box, share buttons, the comments below an article, a sign-in prompt, buttons, and hidden text (a hidden menu, the text of a closed `details` element).

## The numbers

Make words from a text: lower case, letters and digits only. Compare as multisets.

- **Found** for a page = the main words that are in the kept text, divided by all main words of the page.
- **Noise share** for a page = the kept words that are not main words and not neutral words, divided by all kept words.
- **Search**: the correct page is in the first 3 results for the question.
- **Main points**: for a page of `points.tsv`, count the marked sentences that are in the 5 selected sentences.

The pass numbers are in the spec.

## The mark rule for `points.tsv`

"The 3 sentences that a reader must know from this page: the main statement or decision, the key number, and the key date or limit, if the page has them."

## What the set has (no page ids here)

- 10 pages have no landmark element and no landmark role. 2 use ARIA roles and no landmark elements. Some have only a part of the landmarks.
- Kinds: news, blog, documentation, product, forum, recipe, encyclopedia, authority service, pricing, job, how-to, event, terms, web mail, web editor, paper abstract, magazine, release notes, question and answers, school letter, booking, service notice, product test, course lesson.
- Hard cases by design: a box with an advertisement or a newsletter form in the middle of the body; main paragraphs with many links; a page where the main text is 103 words and the links are more; main text in a table layout; main text in an editable area; a cookie notice as a dialog and one as a plain block; hidden text; a list of other mails that repeats the first words of the main mail.
- Some pages have the same places and things on purpose (a boiler, a trip, a street), so that a question can find the wrong page.
- English only.
