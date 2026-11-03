# Wake bench (E5)

This bench compares two wake methods for any phrase that the owner picks. The record is [E5](../../docs/experiments/E5-wake-templates.md).

- **Spotter.** The method in `app/Sources/EarshotWake`. The bench runs the ONNX twin of the same model and a Python port of `StreamingKwsDecoder` and `ContextGraph`.
- **Audio templates.** Query by example. The bench keeps the encoder frames of the owner's 5 teach takes and matches them against the live encoder frames with a streaming DTW (dynamic time warping).

The bench runs in Python on a Linux or Mac computer. It is not part of the app. It uses synthetic voices, not the owner's voice. Live tests stay on the owner's Mac.

## Data

All data goes to `data/` next to this file, or to the folder in `WAKE_DATA`. The folder is not in the repository.

| Folder | Content | Source |
|---|---|---|
| `kws/` | The spotter in ONNX: encoder, decoder, joiner, `tokens.txt`, `bpe.model` | [mobilebytesensei/sherpa-onnx-kws-zipformer-gigaspeech-3.3M](https://huggingface.co/mobilebytesensei/sherpa-onnx-kws-zipformer-gigaspeech-3.3M), a copy of the k2-fsa/sherpa-onnx `kws-models` release (Apache-2.0) |
| `piper/` | 3 Piper voices: `en_US-libritts_r-medium`, `en_GB-vctk-medium`, `en_US-arctic-medium` | [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) |
| `libri/` | LibriSpeech `test-clean` and `test-other`, 10.7 h of read speech by 73 speakers | [openslr.org/12](https://www.openslr.org/12) (CC BY 4.0) |

## Steps

1. Install the tools: `uv sync`.
2. Get the data above into `data/`.
3. Run all steps: `./run_all.sh`. A full run takes many hours. Each step skips the work that is done, so you can stop the script and start it again.

The script does these steps in order:

1. Make the encoder frames of LibriSpeech: `libri_frames.py 0 1`. To use 2 processes, run `libri_frames.py 0 2` and `libri_frames.py 1 2`.
2. Make the synthetic data for each voice index 0 to 9: `gen.py <index>` and `gen_far.py <index>`.
3. Run every method for each voice: `NOCROSS=1 eval_voice.py <voice> 0.75`. A voice name is the model and the speaker, for example `libritts12`. The number is the hours of LibriSpeech for the spotter, which is slow in Python.
4. Score other voices that say the owner's phrase: `cross.py`.
5. Run the far-field commands: `eval_far.py`.
6. Print the tables: `analyse.py`, `analyse.py sweep` (the template limits) and `analyse.py far`.

## Files

| File | What it does |
|---|---|
| `paths.py` | The data folder (`WAKE_DATA`, or `data/`) |
| `kws.py` | Streaming encoder (320-dim frames, 40 ms each) and greedy token decoding, as `TokenReader` in Swift |
| `kwsdec.py` | Port of the Swift keyword decoder: beam 4, 1 trailing blank, keyword boost, the 1.5 s reset as an option |
| `qbe.py` | Audio templates: streaming subsequence DTW, the score and the worst-part score |
| `common.py` | The speech span of a take (as `SpeechTrim`), templates, data loaders |
| `tts.py` | Piper voices with random speed and variation |
| `gen.py` | Synthetic data for one voice: 10 teach takes and 12 test commands per phrase, 6 minutes of own talk, sound-alikes |
| `gen_far.py` | 6 far-field test commands per phrase: room echo, half the volume, pink noise |
| `eval_voice.py` | Runs all methods on one voice and saves the raw scores |
| `cross.py` | Other voices that say the phrase, before the voice check |
| `eval_far.py` | The spotter and the templates on the far-field commands |
| `analyse.py` | Hit rate, false wakes, sound-alikes and delay for each method |
| `run_all.sh` | All steps in order |

## Voice check bench (E6)

These scripts measure the owner voice check. The record is [E6](../../docs/experiments/E6-voice-check.md). They use the same tools (`uv sync`) and a `voice/` folder in the data folder.

| Folder | Content | Source |
|---|---|---|
| `voice/wespeaker.onnx` | WeSpeaker ResNet34-LM in ONNX, the twin of the app's Core ML voice model | [Wespeaker/wespeaker-voxceleb-resnet34-LM](https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34-LM), file `voxceleb_resnet34_LM.onnx` (CC BY 4.0) |
| `voice/LibriSpeech/dev-clean-2/` | Mini LibriSpeech, 26 speakers | [openslr.org/31](https://www.openslr.org/31), file `dev-clean-2.tar.gz` (CC BY 4.0) |

| File | What it does |
|---|---|
| `voice_bench.py` | The mel features and the trim of the app, and the padding study: zero, repeat and no padding; mean, max and top-2 of the takes |
| `voice_joint.py` | The phrase as a gate, then the whole turn as the decision |
| `voice_lengths.py` | The owner and other voices at each speech length, for the limit line |
| `voice_session.py` | A short follow-up turn against the owner's last passed turn, and against the profile |

Run each one with `uv run python <file>`. Each run takes about 10 to 20 minutes on one CPU.
