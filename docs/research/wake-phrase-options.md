# Wake phrase and owner voice for always-on: options

Date: 2026-11-02. Status: research and tests for D-11. The default phrase changed to "hey jarvis" after the tests in section 4.5.

## 1. The ask

The owner wants always-on mode to start only on a wake phrase or a name, as "Hey Siri" does. earshot must react only to the owner's voice. The owner wants a lightweight version of a project that already solves this.

This changes R-ON-1. Today R-ON-1 says that earshot "does not need a key press or a wake word to start".

## 2. The pattern that solves it

"Hey Siri" and the Picovoice "personalized wake word" recipe use the same two stages:

1. A small detector listens all the time for one phrase. It costs little CPU.
2. When the phrase fires, a speaker model compares the voice with the owner's enrolled voice. Only a match continues.

The 2020 Personalized Voice Trigger Challenge uses the same design. Its baseline averages the embeddings of 3 enrolment phrases and compares new phrases with that average.

## 3. Projects found

GitHub search on 2026-11-02. Stars and dates come from the GitHub search API. Accuracy numbers are vendor numbers unless marked.

| Project | What it does | Licence | Stars, last push | Mac and Swift | Fit for earshot |
|---|---|---|---|---|---|
| k2-fsa/sherpa-onnx | Open-vocabulary keyword spotting (any phrase as text, no training), speaker identification, Silero VAD | Apache-2.0 | 15,687, 2026-10-29 | C++ with ONNX Runtime. Swift through a static xcframework that a build or fetch script makes. Runs on Intel. | Good models. Heavy to package. |
| soniqo/speech-swift | The same keyword spotter as CoreML (`SpeechWakeWord`), WeSpeaker speaker embeddings, Silero VAD, Smart Turn | Apache-2.0 (code); models vary | 1,260, 2026-10-30 | SwiftPM. Package needs macOS 15. The VAD and speaker parts pull in MLX. | Best source to copy from. Do not add the whole package. |
| livekit/livekit-wakeword | Trained wake word classifier, openWakeWord compatible, Swift SDK | Apache-2.0 | 304, 2026-10-23 | SwiftPM, macOS 14+, ONNX Runtime with the CoreML provider | Fewest false alarms (0.08 per hour on "hey livekit"). Each phrase needs a trained model. |
| dscripka/openWakeWord | Trained wake word models, optional "custom verifier" for known voices | Apache-2.0 (code); ready models CC BY-NC-SA 4.0 | 2,906, 2025-12-30 | Python only | Ready models are non-commercial. Custom phrase needs training. |
| Picovoice Porcupine + Eagle | Wake word + speaker recognition, the full recipe | SDK Apache-2.0; engine closed | 5,018 and 58 | Swift SDKs | Needs an online access key. Closed engine. Reject (R-MD-4). |
| openclaw/Swabble | Wake word as a text match on Apple SpeechAnalyzer output | MIT | 33, 2026-10-22 | Swift, macOS 26 | No model, but no voice check, and speech to text runs on all speech. This is close to earshot now. |
| cyburke/hey-codex | macOS menu-bar wake phrase app on sherpa-onnx | GPL-3.0 | 5, 2026-07-27 | Swift, macOS 14.4+ | Proof that the sherpa-onnx spotter works in a Swift menu-bar app. Do not copy code (GPL). |
| FluidInference/FluidAudio | Silero VAD, speaker embeddings, ASR on CoreML | Apache-2.0 | 3,253, 2026-11-01 | SwiftPM | No wake word. A speaker embedding option. |
| rhasspy-wake-raven, EfficientWord-Net | Few-shot wake word from 3 recordings of the owner (template or siamese match) | MIT, Apache-2.0 | 61 (archived), 319 | Python | Personal by design, but old or Python. Not checked in detail. |
| kahrendt/microWakeWord | Tiny trained models for microcontrollers (Home Assistant) | Apache-2.0 | not checked | TFLite | Needs training. Not checked in detail. |

## 4. Recommendation

Use the open-vocabulary keyword spotter for the phrase and a speaker embedding for the voice. Take only the parts that earshot needs.

### 4.1 Wake phrase

- Model: icefall KWS Zipformer, gigaspeech fine-tune, 3.49M parameters, Apache-2.0. CoreML INT8 conversion `aufklarer/KWS-Zipformer-3M-CoreML-INT8`.
- Size: encoder 3.3 MB, decoder 525 KB, joiner 160 KB, BPE vocabulary 239 KB.
- Minimum OS: macOS 14 (model card). It uses explicit cache tensors, not MLState. So it fits the macOS 14 and Intel build of PR #61.
- Speed (model card): encoder 5.4 ms for each 320 ms of audio, about 1.7 % of one core while it listens.
- Memory (model card): about 63 MB more resident memory after load.
- Accuracy (model card): recall 0.88 on 12 keywords in clean speech; 0.27 false positives per negative utterance on 60 utterances. These are small tests. Measure on the owner's Mac.
- The phrase is plain text. The default is "hey jarvis" (it was "hey earshot" before the tests in section 4.5). A two-word phrase fires less often by mistake than one word (hey-codex warns that "single words go off when you did not mean them").

### 4.2 Owner voice

- Model: WeSpeaker ResNet34-LM (6.6M parameters, 256-dim embedding). CoreML conversion `aufklarer/WeSpeaker-ResNet34-LM-CoreML`, about 25 MB. The card says MIT. The source weights are trained on VoxCeleb, which WeNet lists as CC BY 4.0, so credit them in THIRD_PARTY_NOTICES.
- Enrolment: in Manage, the owner says the wake phrase 5 times. earshot keeps the average embedding on the Mac. It never keeps the audio.
- Check: at each wake, compare the embedding of the phrase audio with the enrolled one (cosine). If the turn is long enough, check the whole turn too. Tune the threshold from the trial log.
- Limit: speaker models are less sure on short audio. The vendor advises 2 to 3 s. A fixed phrase helps, because enrolment and test say the same words.

### 4.3 How it changes the earshot pipeline

```
mic ─► keyword spotter ("hey jarvis") ─► voice check ─► turn ─► speech to text ─► router ─► actions
        always on, ~2 % CPU                 owner only      550 ms end    strip the phrase
```

1. Speech without the phrase never reaches speech to text. So earshot keeps no text of overheard speech.
2. The speech engine keeps 3 s of audio. A wake turn starts at the start of the phrase (the usual preroll is 250 ms). So the words after the phrase are not lost when the spotter fires late.
3. The "for me?" prefix rule is no longer needed in always-on. The follow-up window stays: for 5 s after a command, the owner's voice alone continues.
4. The safety rules do not change. Always-on never sends and never presses a risky button (R-ON-5).
5. The hold key stays as the fallback (R-ON-4).

### 4.4 Why this is the lightweight version

- No new package dependency. Copy the 10 Swift files of `SpeechWakeWord` from speech-swift (about 2,200 lines, CoreML and Accelerate only) into a new earshot target, with the Apache-2.0 notice. Add a small wrapper for the voice model.
- The whole speech-swift package needs macOS 15 and pulls in MLX. That would break the macOS 14 and Intel build.
- sherpa-onnx needs a C++ static framework, ONNX Runtime and a fetch script.
- Models download once from Hugging Face (about 30 MB), at a pinned revision with a SHA-256 check. The owner does no setup except the 5-phrase enrolment.

### 4.5 Tests on synthetic voices (2026-11-02)

I ran the same spotter model (the ONNX version, sherpa-onnx) in the cloud container. The voices are 10 synthetic "owner" voices from one Piper text-to-speech model (LibriTTS-R), each clean and with noise at 10 dB SNR (signal-to-noise ratio). The 800 negatives are 20 phrases of other talk, which include sound-alikes ("hey, your shot", "keep it out of earshot of the kids"). Real voices and a real room can give other numbers.

| Phrase and keyword source | Owner phrases that woke it | Other talk that woke it | Delay after the phrase (median) |
|---|---|---|---|
| "hey earshot", spelled tokens | 7 of 168 (4 %) | 0 of 600 | 476 ms |
| "hey earshot", tokens learned from 3 owner phrases | 61 of 80 (76 %) | 47 of 800 | 458 ms |
| "hey earshot", tokens learned from 5 owner phrases | 64 of 80 (80 %) | 53 of 800 | 470 ms |
| "hey computer", spelled tokens | 58 of 80 (72 %) | 0 of 800 | 274 ms |
| "hey jarvis", spelled tokens | 69 of 80 (86 %) | 0 of 800 | 325 ms |

What the tests show:

1. The model does not know the made-up word "earshot". It hears "YOUR SHOT", "HERE SHUT" or "YOU'RE SHOT". So the spelled tokens almost never fire.
2. Tokens learned from the owner's own phrases fix the misses. But then the sound-alikes "hey, your shot", "hey, you are shot" and "hey, here, shut the door" also wake it. All the other negatives stayed at 0.
3. A phrase of real words ("hey jarvis") needs no learned tokens, wakes most often, never woke on other talk, and is the fastest.
4. The spotter wakes for other voices too (37 of 40 for "hey jarvis"). The voice check must stop them.
5. The voice check on these synthetic voices: half total error 14 to 16.5 % at the best threshold. One text-to-speech model makes voices that are more alike than real people. Measure on the owner's voice.
6. Speed: 13.2 s of audio in 197 ms on one container CPU core (x86). One voice embedding: 39 ms.

The code supports any phrase. At enrolment, earshot checks whether the spelled tokens fire on the owner's 5 phrases. If they do not, it adds the tokens that it heard.

## 5. Risks and open points

- Accuracy is not measured on the owner's voice or room. A trial must log each wake, each voice score and each miss.
- The spotter is English only.
- Intel Macs run CoreML on the CPU. Speed there is not measured.
- WeSpeaker input shape and minimum OS are not on the model card. Read the speech-swift code before use.
- If the spotter fires too often, a trained livekit-wakeword model for the phrase is the upgrade. It needs a training run (synthetic clips), not new app code.

## 6. Requirement and decision changes

- R-ON-1: earshot listens all the time. It starts on the owner's wake phrase (default "hey jarvis"). No key press is needed.
- R-ON-3: Must for always-on. earshot acts only on the enrolled owner's voice.
- New decision D-11: wake phrase + owner voice replaces the no-wake-word gate, because the word gate passes common words in normal talk and has no voice check.

## 7. Sources

- k2-fsa/sherpa-onnx: https://github.com/k2-fsa/sherpa-onnx and keyword spotting docs: https://k2-fsa.github.io/sherpa/onnx/kws/index.html
- soniqo/speech-swift: https://github.com/soniqo/speech-swift, wake word guide: https://soniqo.audio/guides/wake-word, speaker guide: https://soniqo.audio/guides/embed-speaker
- KWS CoreML model card: https://huggingface.co/aufklarer/KWS-Zipformer-3M-CoreML-INT8
- WeSpeaker CoreML model card: https://huggingface.co/aufklarer/WeSpeaker-ResNet34-LM-CoreML and WeNet licence note: https://github.com/wenet-e2e/wespeaker/blob/master/docs/pretrained.md
- livekit/livekit-wakeword: https://github.com/livekit/livekit-wakeword
- dscripka/openWakeWord: https://github.com/dscripka/openWakeWord and custom verifier: https://github.com/dscripka/openWakeWord/blob/main/docs/custom_verifier_models.md
- Picovoice Porcupine: https://github.com/Picovoice/porcupine, Eagle: https://github.com/Picovoice/eagle, recipe: https://picovoice.ai/cookbook/personalized-wake-word/
- openclaw/Swabble: https://github.com/openclaw/Swabble
- cyburke/hey-codex: https://github.com/cyburke/hey-codex
- FluidInference/FluidAudio: https://github.com/FluidInference/FluidAudio
- rhasspy/rhasspy-wake-raven: https://github.com/rhasspy/rhasspy-wake-raven and Ant-Brain/EfficientWord-Net: https://github.com/Ant-Brain/EfficientWord-Net
- kahrendt/microWakeWord: https://github.com/kahrendt/microWakeWord
- 2020 Personalized Voice Trigger Challenge: https://arxiv.org/pdf/2101.01935
