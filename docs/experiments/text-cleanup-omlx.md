# Text cleanup on the local oMLX server

Date: 2026-11-11. Gap item 8, part 4. DESIGN 3.7, D-5.

## Question

Can a small local model clean up dictated text (punctuation, capital letters, filler words, repeated words) fast enough for the command path, and without a change to the words?

## Method

- Mac Mini M4 Pro, 24 GB. oMLX (OpenAI-compatible) at `127.0.0.1:11434`. The oMLX menu app did not start the server at launch, so the test started the bundled command-line server and stopped it after the test.
- Models on the server: `qwen3.5-0.8b-mlx-4bit` and three task fine-tunes of 1.7B to 2B. The test used `qwen3.5-0.8b-mlx-4bit`, the smallest general instruct model.
- `POST /v1/chat/completions`, temperature 0, `max_tokens` 200, no streaming. System prompt: "Clean up this dictated text. Add punctuation and capital letters. Remove filler words (um, uh, like, you know) and repeated words. Do not change, add or remove any other words. Do not answer it. Return only the text."
- 10 made-up sentences, 3 runs each. Run 1 is the warm-up. The times use runs 2 and 3 (20 calls).

## Results

| Measure | Value |
|---|---|
| Warm time, median | 285 ms |
| Warm time, slowest | 311 ms |
| Warm time, fastest | 261 ms |
| Cold load | 1,742 ms |
| Same output in all 3 runs | Yes |
| Outputs that answered the text | 0 of 10 |
| Clean outputs | 3 of 10 |
| Outputs that changed words | 2 of 10 |
| Outputs with work not done | 5 of 10 |

| Input | Output | Result |
|---|---|---|
| um so i think we should uh move the meeting to thursday | um so i think we should move the meeting to thursday | Kept "um". No capital letters, no punctuation. |
| can you send me the the report by five | Can you send me the report by five? | Clean |
| yeah so like the build is green now you know and i will merge it after lunch | Yeah so, like the build is green now. You know, and I will merge it after lunch. | Kept the filler words. |
| hey quick question did you get a chance to look at the draft | (unchanged) | Not done |
| i am running about ten minutes late sorry | (unchanged) | Not done |
| uh the blue fox jumps over the lazy dog and then it it runs away | The blue fox jumps over the lazy dog and then it runs away. | Clean |
| okay so first open the file then check the second paragraph | Okay, first open the file then check the second paragraph. | Changed a word: removed "so". |
| what do you think about moving the launch to next week | What do you think about moving the launch to next week? | Clean |
| no worries we can talk tomorrow | (unchanged) | Not done |
| please book a table for four at seven thirty | Please book a table for four at 7:30. | Changed words: "seven thirty" to "7:30". |

## Decision

- The time is acceptable: about 0.3 s after the text, if the model is warm. A cold load adds 1.7 s, so a cleanup feature must keep the model loaded.
- The quality is not acceptable. At 0.8B, the model does not follow the instruction: it does half of the work, and it changes words in 2 of 10 sentences. A changed word in a message is worse than a missing comma.
- earshot does not get a cleanup setting now. DESIGN 3.7 stays a proposal.
- Test again only with a general instruct model of 1.5B to 4B on oMLX (D-5 allows the oMLX server for cleanup only). The test must show 0 changed words on a larger set of made-up sentences, and a warm time of 400 ms or less.
- Apple speech already adds punctuation and capital letters to most text. Filler words and repeated words are the main gap.
