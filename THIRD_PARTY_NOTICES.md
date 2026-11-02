# Third-party notices

earshot uses the parts in this file. Each part has its own license. The earshot MIT License does not apply to them.

## Included in the app bundle

### transcribe.cpp

- Project: https://github.com/handy-computer/transcribe.cpp
- Version: 0.3.1, prebuilt `TranscribeCpp.xcframework`
- License: MIT
- Use: runs the Parakeet speech model on the Mac.
- Swift Package Manager downloads the framework at build time and checks its SHA-256 sum (`app/Package.swift`). `app/scripts/build-app.sh` copies `CTranscribe.framework` into the app bundle.

If you give a copy of a built `Earshot.app` to other people, include the transcribe.cpp license text with it.

## Not included

### NVIDIA Parakeet model weights

- License: CC BY 4.0
- earshot does not include and does not download a Parakeet model file. The owner sets the path to a GGUF file, or earshot reads the file of the Hex app if it is installed. earshot never changes, moves or copies that file.
- If you give a Parakeet model file to other people, credit NVIDIA as CC BY 4.0 requires.

### Apple frameworks

earshot uses Apple system frameworks (Speech, AVFoundation, Accessibility, AppKit, SwiftUI, ScreenCaptureKit, Vision, Contacts). They are part of macOS. The repository does not include them.

## Brand assets

The earshot wordmark in `assets/brand/` uses the Inter Display Bold font, converted to outlines. Inter is licensed under the SIL Open Font License 1.1 (https://github.com/rsms/inter). The repository does not include the font file.

## Build tools for the brand assets

`assets/brand/render.py` uses Python packages that `uv` installs from `assets/brand/uv.lock`. These tools are not part of the app.
