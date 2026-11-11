# E10: an embedding model for the PA plugin

Status: open. Candidates 1 and 2 are measured and fail. Candidates 3 and 4 are next.

Source: the PA phase 2 build spec, section 6 (`/mnt/project-files/earshot-pa/phase2-build-spec.md` in the project folder). Requirements: R-PA-4, R-PA-8, R-MD-4.

## Question

Which embedding model lets the PA find a kept document or an item by sense, and propose a project for a capture? The PA selects the model by numbers, not by name. It selects the first candidate in the order below that passes the marks "Search" and "Project" on the holdout set.

## Candidates, in the order of their cost for the owner

| Order | Candidate | Cost for the owner |
|---|---|---|
| 1 | `NLEmbedding.sentenceEmbedding` (macOS) | None |
| 2 | `NLContextualEmbedding` (macOS), mean of the token vectors | None, or one system download |
| 3 | Qwen3-Embedding-0.6B | A model download by the install script, and a model runtime in the PA |
| 4 | EmbeddingGemma-300M | A model download by the install script, and a model runtime in the PA |

## Method

- The fixtures are made-up: `plugins/pa/Tests/PACoreTests/Fixtures/phase2/`. They have 10 projects, 40 documents, 120 items, 100 development questions, 100 holdout questions, 100 development captures, 100 holdout captures, 10 documents with marked main points, and 40 pairs for the duplicate notice. The holdout files were written before any score.
- Search: each document is cut into passages of about 120 words. The index has the passages and the item titles. For a question, the bench merges the keyword list (SQLite FTS5 with the porter stem rule, bm25) and the list by numbers (cosine) with reciprocal rank fusion, 1 / (60 + rank). A hit is the correct document or item in the first 3.
- Project: the profile of a project is the mean of the numbers of its name, its item titles and its passages. The rule proposes the best project only if its score is above A and its distance to the second project is above B. The bench finds A and B on the development captures (the most proposals with 3 or fewer wrong), then counts on the holdout.
- The bench: `earshot-pa --embed-bench <fixtures> --embedder <name> [--dims 256]`. CI prints the table on `macos-26` for each macOS candidate.

## Marks

| Mark | Pass |
|---|---|
| Search | Holdout: the correct result in the first 3 for 90 or more of 100. |
| Project | Holdout: 90% or more of the proposals correct, and 5 or fewer wrong proposals in 100. |
| Speed | One query: 100 ms or less. |
| Memory | Less than 50 MB after the model unloads. |

## Results: candidates 1 and 2

CI run on `macos-26`, PR #142, 2026-11-11. "Keywords only" is the base with no model.

| Measure | Keywords only | 1: sentence, 512 | 1: sentence, 256 | 2: contextual, 256 |
|---|---|---|---|---|
| Search holdout, first 3 (merged) | 78 | 63 | 61 | 65 |
| Search holdout, numbers only | not used | 23 | 23 | 25 |
| Search holdout, lines with other words (49) | 37 | 30 | 29 | 32 |
| Search development, first 3 (merged) | 76 | 54 | 54 | 68 |
| Project holdout: proposals, correct, wrong | not used | 7, 4, 3 | 9, 5, 4 | 9, 6, 3 |
| Duplicates: same pairs found, different pairs called the same (of 20 each) | not used | 17, 7 | 18, 7 | 12, 4 |
| Main points: documents with 2 or more marks (of 10) | not used | 3 | 3 | 2 |
| One query, median | not used | 5.7 ms | 6.8 ms | 15.7 ms |
| First load | not used | 179 ms | 130 ms | 2,217 ms |

The full-length run of candidate 2 (768 numbers) did not start in this CI run: the first request for the system data gave no answer in time. The run with 256 numbers then found the data. The bench now checks the state of the data after the request.

## Finding

- Both macOS candidates fail Search and Project. The merged list is worse than the keywords alone, because the list by numbers puts the correct result in the first 3 for only about 1 question in 4.
- So the PA does not use candidate 1 or 2. By section 6.2 of the build spec, candidates 3 and 4 come next. Both need a model download in the install script and a model runtime in the PA.
- Candidate 3 (Qwen3-Embedding-0.6B) has the Apache 2.0 license. Candidate 4 (EmbeddingGemma-300M) has the Gemma terms. If both pass, the spec prefers the open-source license (R-MD-4).

## Next

1. Select a runtime for candidates 3 and 4 from the current documents of the runtime.
2. Run the bench for candidates 3 and 4, and run the project test on dk's 100 research items (build spec 6.4). The items are made-up and stay out of this repository.
3. Record the decision as D-16 in `docs/DECISIONS.md`.
