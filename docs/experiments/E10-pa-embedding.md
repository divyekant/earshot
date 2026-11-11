# E10: an embedding model for the PA plugin

Status: closed. Only candidate 4 (EmbeddingGemma-300M) passes Search. No candidate passes Project. The owner selected candidate 4 with 768 numbers on 2026-11-11 (D-16).

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

## Results: candidates 3 and 4

The Mac Mini (Apple M4 Pro), branch `claude/project-thread-x9ssv9` at 1689938, 2026-11-11. Runtime: llama.cpp b12284 (the macOS xcframework, Metal). Model files: Q8_0 GGUF at a fixed revision with a SHA-256 check (`plugins/pa/scripts/get-model.sh`). One CI run of these candidates used all of the 30 minutes of the job, so CI only checks the download.

| Measure | Keywords only | 3: Qwen3, 1024 | 3: Qwen3, 256 | 4: Gemma, 768 | 4: Gemma, 256 |
|---|---|---|---|---|---|
| Search holdout, first 3 (merged) | 78 | 86 | 86 | **92** | **90** |
| Search holdout, numbers only | not used | 83 | 73 | 94 | 88 |
| Search holdout, lines with other words (49) | 37 | 42 | 41 | 43 | 42 |
| Search development, first 3 (merged) | 76 | 87 | 88 | 92 | 92 |
| Project holdout: proposals, correct, wrong | not used | 36, 30, 6 (83%) | 43, 31, 12 (72%) | 48, 41, 7 (85%) | 47, 38, 9 (81%) |
| Project, dk's 100 items (rule of the development set): proposals, correct, wrong | not used | 11, 10, 1 | 11, 10, 1 | 13, 12, 1 | 7, 6, 1 |
| Project, dk's items, best project with no threshold (of 75) | not used | 58 | 56 | 58 | 54 |
| Duplicates: same pairs found, different pairs called the same (of 20 each) | not used | 17, 0 | 17, 0 | 19, 0 | 18, 0 |
| Main points: documents with 2 or more marks (of 10) | not used | 4 | 2 | 1 | 1 |
| One query, median (GPU) | not used | 12.6 ms | 12.6 ms | 4.6 ms | 4.1 ms |
| One passage, median (GPU) | not used | 33.9 ms | 34.1 ms | 12.0 ms | 12.3 ms |
| Embed the index, 200 texts (GPU) | not used | 3.5 s | 3.1 s | 1.8 s | 1.5 s |
| Load and first text | not used | 174 ms (4.0 s after the download) | 174 ms | 432 ms | 154 ms |
| Footprint with the model loaded | not used | 501 MB | 337 MB | 322 MB | 215 MB |

Qwen3 with 1024 numbers on the CPU only: the same quality, but one query takes 369 ms and one passage takes 1,496 ms. So the PA must use the GPU.

The 4B model of dk's research put 90% of dk's items in the correct project. With no threshold, the best project of candidate 3 or 4 is correct for 54 to 58 of the 75 items with a project (72% to 77%). With the rule of the development set, few items get a proposal.

## Finding

- Candidates 1 and 2 (macOS) fail Search and Project. The list by numbers puts the correct result in the first 3 for only about 1 question in 4.
- Candidate 3 (Qwen3-Embedding-0.6B, Apache 2.0) fails Search: 86 of 100. It also fails Project.
- Candidate 4 (EmbeddingGemma-300M, Gemma terms) passes Search: 92 with 768 numbers, 90 with 256. It fails Project: 85% correct and 7 wrong proposals. The marks are 90% and 5.
- So no candidate passes Project. By section 6.5 of the build spec, the PA builds search (Q3) and main points (Q5) with the model that passes Search, and the project proposals of Q4 stay off by default (`"proposeProject": false`).
- The only model that passes Search does not have an open-source license. R-MD-4 prefers an open-source license, so the owner decides (D-16).
- The 768 numbers of candidate 4 are 2 points better on the holdout than 256 numbers, for 107 MB more memory while the model is loaded. The compare of 50,000 passages takes 23 ms with 768 numbers and 6 ms with 256.
- In bench mode, the program stopped at exit in the Metal teardown of llama.cpp, after the table, because the model was still loaded. The bench now frees the model before exit. The PA must also free the model before it stops (Q3).

## Next

1. Done: the owner selected EmbeddingGemma-300M (D-16).
2. Q3: load the model when it is needed, unload it after a quiet time, and free it before exit.
