# Third-party notices

earshot uses the parts in this file. Each part has its own license. The earshot MIT License does not apply to them.

## Included in the app bundle

### transcribe.cpp

- Project: https://github.com/handy-computer/transcribe.cpp
- Version: 0.4.1, prebuilt `TranscribeCpp.xcframework`
- License: MIT
- Use: runs the Parakeet speech model on the Mac.
- Swift Package Manager downloads the framework at build time and checks its SHA-256 sum (`app/Package.swift`). `app/scripts/build-app.sh` copies `CTranscribe.framework` into the app bundle.

If you give a copy of a built `Earshot.app` to other people, include the transcribe.cpp license text with it.

### speech-swift (copied source files)

- Project: https://github.com/soniqo/speech-swift, commit `a57702e`
- License: Apache-2.0. The full text is in `LICENSES/Apache-2.0.txt`. The project has no NOTICE file.
- Use: the keyword spotter code (`Sources/SpeechWakeWord`) and the speaker embedding code (`Sources/SpeechVAD`, Core ML path only) run the wake phrase and the voice check of always-on mode (D-11). The turn model code (`Sources/SpeechVAD/SmartTurn.swift`, Core ML path only) checks the end of an always-on turn (R-ON-1).
- The copied files are in `app/Sources/EarshotWake/KWS`, `app/Sources/EarshotWake/Voice` and `app/Sources/EarshotWake/Turn`. Each file names its source file and the earshot changes in its first lines. earshot does not depend on the speech-swift package.

## Not included

### NVIDIA Parakeet model weights

- License: CC BY 4.0
- earshot does not include and does not download a Parakeet model file. The owner sets the path to a GGUF file, or earshot reads the file of the Hex app if it is installed. earshot never changes, moves or copies that file.
- If you give a Parakeet model file to other people, credit NVIDIA as CC BY 4.0 requires.

### Wake phrase models (always-on mode)

earshot downloads these model files from Hugging Face one time, when the owner turns on always-on mode. It uses pinned revisions and checks the SHA-256 sum of each file (`app/Sources/EarshotWake/ModelFiles.swift`). The files go to `~/Library/Application Support/earshot/models/`. The repository and the app bundle do not include them.

- Keyword spotter: icefall KWS Zipformer (gigaspeech fine-tune, 3.49M parameters), from `pkufool/keyword-spotting-models`. Core ML conversion: https://huggingface.co/aufklarer/KWS-Zipformer-3M-CoreML-INT8 at revision `45929a2`. License: Apache-2.0.
- Voice model: WeSpeaker ResNet34-LM, trained on VoxCeleb, from https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM. Core ML conversion: https://huggingface.co/aufklarer/WeSpeaker-ResNet34-LM-CoreML at revision `b358f33` (the conversion card says MIT). The source weights are CC BY 4.0. Credit: WeSpeaker (https://github.com/wenet-e2e/wespeaker) and VoxCeleb (https://www.robots.ox.ac.uk/~vgg/data/voxceleb/).
- Turn model (optional): Smart Turn v3.2 by Daily (https://github.com/pipecat-ai/smart-turn), BSD-2-Clause. Core ML conversion: https://huggingface.co/aufklarer/Smart-Turn-v3.2-CoreML at revision `75f0697` (about 17 MB). If the download fails, the end silence alone ends a turn.
- If you give these model files to other people, keep these credits with them.

### Apple frameworks

earshot uses Apple system frameworks (Speech, AVFoundation, Accessibility, AppKit, SwiftUI, ScreenCaptureKit, Vision, Contacts). They are part of macOS. The repository does not include them.

## Brand assets

The earshot wordmark in `assets/brand/` uses the Inter Display Bold font, converted to outlines. Inter is licensed under the SIL Open Font License 1.1 (https://github.com/rsms/inter). The repository does not include the font file.

The landing page in `site/` includes two font files: Schibsted Grotesk (https://github.com/schibsted/schibsted-grotesk) and JetBrains Mono (https://github.com/JetBrains/JetBrainsMono). Both are licensed under the SIL Open Font License 1.1. The license texts are in `site/fonts/`.

## Build tools for the brand assets

`assets/brand/render.py` uses Python packages that `uv` installs from `assets/brand/uv.lock`. These tools are not part of the app.
