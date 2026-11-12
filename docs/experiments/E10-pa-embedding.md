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

## Results: candidate 5, EmbeddingGemma 2

The owner asked for a run of EmbeddingGemma 2 (Apache 2.0, September 2026, after the spec). The run uses the text model only (`embeddinggemma-2-Q8_0.gguf` of ggml-org, 310 MB). The image and audio part (`mmproj`, 555 MB) is not used. The same Mac, llama.cpp b12284, Metal, 2026-11-11.

| Measure | 4: Gemma, 768 | 5: Gemma 2, 768 | 5: Gemma 2, 256 |
|---|---|---|---|
| Search holdout, first 3 (merged) | **92** | 87 | 86 |
| Search holdout, numbers only | 94 | 83 | 77 |
| Search development, first 3 (merged) | 92 | 89 | 90 |
| Project holdout: proposals, correct, wrong | 48, 41, 7 (85%) | 43, 38, 5 (88%) | **33, 30, 3 (91%)** |
| Project, dk's items (rule of the development set): proposals, correct, wrong | 13, 12, 1 | 8, 7, 1 | 8, 7, 1 |
| Project, dk's items, best project with no threshold (of 75) | 58 | 54 | 52 |
| Duplicates: same pairs found, different pairs called the same (of 20 each) | 19, 0 | 20, 2 | 19, 1 |
| One query, median | 4.6 ms | 6.4 ms | 6.3 ms |
| One passage, median | 12.0 ms | 17.4 ms | 17.8 ms |
| Footprint with the model loaded | 322 MB | 392 MB | 290 MB |

EmbeddingGemma 2 fails Search (87 and 86). With 256 numbers, it passes Project on the holdout (91% correct, 3 wrong). On dk's items, the rule makes only 8 proposals for 75 items with a project.

The first run read only 512 of the 768 numbers, because the code took the width of the model (512) as the size of the output. The code now asks llama.cpp for the size of the output.

## The floor of the search (after the Mac test)

The Mac test of Q3 found that "where is passport" gave results, also with no match: the list by numbers had no minimum score. The bench now finds a floor on the development questions: the score of the correct result that 95 of 100 questions reach or pass. Then it checks the holdout with the floor.

| Candidate 4, Gemma, 768 | Value |
|---|---|
| Floor (from the development set) | 0.411 |
| Search holdout, first 3, merged, with the floor | 90 of 100 (92 with no floor) |

With the floor, Gemma is at the Search mark (90), with no margin.

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
- Candidate 5 (EmbeddingGemma 2, Apache 2.0) fails Search: 87 of 100. With 256 numbers it passes Project, but it is a second model, so the PA does not use it now.
- The only model that passes Search does not have an open-source license. R-MD-4 prefers an open-source license, so the owner decides (D-16).
- The 768 numbers of candidate 4 are 2 points better on the holdout than 256 numbers, for 107 MB more memory while the model is loaded. The compare of 50,000 passages takes 23 ms with 768 numbers and 6 ms with 256.
- In bench mode, the program stopped at exit in the Metal teardown of llama.cpp, after the table, because the model was still loaded. The bench now frees the model before exit. The PA must also free the model before it stops (Q3).

## Next

1. Done: the owner selected EmbeddingGemma-300M (D-16).
2. Q3: load the model when it is needed, unload it after a quiet time, and free it before exit.

## Follow-up: project rule version 2 and main points version 2

Spec: `phase2-followup-spec.md`, packages R1 and R2. Model: EmbeddingGemma-300M, 768 numbers, Metal, on the Mac.
New holdout data: `capture-holdout-2.tsv` (100 captures, 30 with no project) and `points-holdout/` (10 documents, 3 marks each).
The holdout data was committed before the rule code. Each holdout ran one time (2026-11-11, 23:34 UTC, commit 5ea27bb).

### R1: project rule version 2

The rule uses only the owner records: items that the owner put in a project, and the passages of documents with a project.
A project needs 3 or more records. The rule proposes a project if:

1. 4 or more of the 5 nearest records (above the search floor) are in the project, and 3 of the first 3 keyword results are in the same project, or
2. only with the setting `proposeByName` (off by default): the capture has the name of exactly one project.

Line 3 of the spec is 5 of 5 neighbors with the nearest score above H. No 5-of-5 case was wrong on the development data, so H is -1 and line 3 fires on any 5 of 5. With needs 4 and 3, line 3 adds 7 correct and 0 wrong on the development data (33 against 26). By the selection rule of the spec, the variant with line 3 is the better one. The selected rule has no line 3, because H gave no real limit. This was a selection error: the holdout ran without line 3, and the PA has no line 3.

Development data (old dev and old holdout, 200 captures, 140 with a project):

| Rule | Proposals | Correct | Wrong |
|---|---|---|---|
| Version 1 | 97 | 87 | 10 |
| Neighbors only (4 of 5) | 45 | 43 | 2 |
| Full rule, keywords 2 of 3 | 41 | 39 | 2 |
| Full rule, neighbors 5 of 5, keywords 2 of 3 | 20 | 20 | 0 |
| **Full rule, neighbors 4 of 5, keywords 3 of 3 (selected)** | **26** | **26** | **0** |
| Full rule, neighbors 5 of 5, keywords 3 of 3 | 13 | 13 | 0 |

Holdout (`capture-holdout-2.tsv`, one run): **20 proposals, 19 correct (95%), 1 wrong. Pass** (mark: 90% or more, 5 or fewer wrong).
19 of 70 captures with a project got a correct proposal.

The owner's 100 labeled research items (75 with a project), development run, not a holdout:

| Rule | Proposals | Correct | Wrong |
|---|---|---|---|
| Version 1 | 16 | 15 | 1 |
| Version 2 with line 3, name line on | 18 | 15 | 3 |
| Version 2 without line 3, name line on (`proposeByName` true) | 13 | 11 | 2 |
| **Version 2 without line 3, name line off (the default in the PA)** | **9** | **8** | **1** |
| Version 2 as in the PA (floor 0.411, 3 or more records, name line off) | 9 | 8 | 1 |

The 4B model of the research session scored 0.90 on these items.

Which line made each proposal (version 2 with line 3 and the name line, 18 proposals):

| Line | Proposals | Wrong |
|---|---|---|
| Name | 5 | 1 |
| Neighbors and keywords | 8 | 1 |
| Line 3 | 5 | 1 |

The 3 wrong proposals:

- Name line: the capture has the name of one project but is for another. The proposed project has 12 records.
- Neighbors and keywords: 4 of 5 and 3 of 3, for a capture with no project. The proposed project has 12 records.
- Line 3: 5 of 5 neighbors and 1 of 3 keywords, for a capture with no project. The proposed project has 6 records.

Few records do not explain the wrong proposals. Two of the three are in the largest project (11 or 12 records). The project with 4 records got 1 correct proposal.

Name line test (`capture-names.tsv`, 20 made-up captures, measured with the name line on and off):

| Captures | Name line on: proposals | Correct | Wrong | Name line off: proposals | Correct | Wrong |
|---|---|---|---|---|---|---|
| For the named project (10) | 10 | 10 | 0 | 7 | 7 | 0 |
| The name words in another sense (10) | 10 | 0 | 10 | 1 | 0 | 1 |

The name line matches words, not meaning. It proposes a project for "the soup kitchen" and for "his Lisbon trip". So the name line is now behind the setting `proposeByName`, off by default. The sure way to name a project is "for <project>" at the end of the capture. No capture of `capture-holdout-2.tsv` has a project name, so the holdout result does not change.

Causes:

- Version 1 compared a capture with the mean of each project. Large projects with many topics (wedding, move) have a wide mean. 6 of the 7 wrong proposals on the old holdout were household captures with no project.
- Version 2 needs two signals that agree. The nearest records see local likeness. The keyword results see rare words. A household capture seldom passes both.
- The cost is coverage: 19 of 70 captures with a project got a proposal, against 41 of 70 for version 1 on the old holdout.
- No capture of `capture-holdout-2.tsv` has the name of a project, so the name line gave 0 proposals in the holdout. The name line test shows that it is wrong for each capture that uses the name words in another sense.
- On the owner's research items, the rule in the PA (name line off) made 1 wrong of 9 (version 1: 1 wrong of 16). The wrong proposals are not from projects with few records.

### R2: main points version 2

Each candidate sentence gets points for its features. The weights were set by hand on the old 10 documents only:
amount 3, date or time limit 3, request 3, result 2, opening 0, title words 0.5 each (at most 1), central by words 1, central by numbers 1, boilerplate -5.
A sentence that is too similar to a selected one (dot product above 0.9) is skipped.

| Data | Documents with 2 or more marks in the 5 | Marks in the 5 | Sentences not in the text |
|---|---|---|---|
| Old documents (development), version 1 | 1 of 10 | — | 0 |
| Old documents (development), version 2 | 9 of 10 | 21 of 30 | 0 |
| **`points-holdout/`, version 2, one run** | **10 of 10** | **24 of 30** | **0** |

**Pass** (mark: 8 or more of 10).

Two limits:

- The marks changed. The follow-up used a new, more exact mark rule (`points-holdout/RULE.md`). Under it, 4 of the 30 marks of the old 10 documents changed. So "10 of 10" here and "1 of 10" in phase 2 are not the same test.
- The same thread wrote the documents, the marks and the mark rule. Real documents can score lower.

Causes:

- Version 1 selected the sentences nearest to the center of the document. The marked sentences (a price, a date, a request) are often not central, so most of them ranked below 5.
- 22 of the 30 development marks have an amount, a date or a request. Version 2 gives points for these features.
- The 6 missed holdout marks have a request or a result, but rank 6 to 10 behind other sentences with an amount or a date.
