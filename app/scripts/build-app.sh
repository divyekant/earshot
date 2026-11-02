#!/bin/bash
# Builds build/Earshot.app from the SwiftPM release build. Run it from any folder.
# It does not open the app. EARSHOT_APP_OUT sets another output path, for example to check a build
# while the app in build/ runs.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release
bin="$(swift build -c release --show-bin-path)"

app="${EARSHOT_APP_OUT:-build/Earshot.app}"
rm -rf "$app"
mkdir -p "$(dirname "$app")" "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$bin/earshot" "$app/Contents/MacOS/earshot"
cp scripts/Info.plist "$app/Contents/Info.plist"
# The VERSION file at the repository root is the one source of the version (docs/RELEASING.md).
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(tr -d '[:space:]' < ../VERSION)" "$app/Contents/Info.plist"
cp ../assets/brand/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# transcribe.cpp (Parakeet). EarshotSpeech finds it at @executable_path/../Frameworks (T1).
cp -R "$bin/CTranscribe.framework" "$app/Contents/Frameworks/"
# Resource bundles of the SwiftPM modules, if any.
for b in "$bin"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$app/Contents/Resources/"; done

# Swift back-deployment (the target is macOS 14): SwiftPM adds an rpath to the Swift toolchain of this Mac,
# for example /Applications/Xcode.app/.../swift-6.2/macosx. Other Macs do not have that folder.
# Copy each Swift library that the binary loads from @rpath and that exists only in the toolchain into
# Contents/Frameworks, then remove the toolchain rpath. /usr/lib/swift and @executable_path rpaths stay.
exe="$app/Contents/MacOS/earshot"
rpaths() { otool -l "$1" | awk '$2 == "LC_RPATH" { getline; getline; print $2 }'; }
for rp in $(rpaths "$exe"); do
    case "$rp" in @*|/usr/lib/swift) continue ;; esac
    for lib in $(otool -L "$exe" | awk '$1 ~ /^@rpath\/libswift/ { sub("@rpath/", "", $1); print $1 }'); do
        if [ -f "$rp/$lib" ] && [ ! -e "$app/Contents/Frameworks/$lib" ]; then
            echo "Bundling $lib from the toolchain"
            cp "$rp/$lib" "$app/Contents/Frameworks/"
        fi
    done
    echo "Removing the toolchain rpath $rp"
    install_name_tool -delete_rpath "$rp" "$exe"
done
if rpaths "$exe" | grep -Ev '^(@|/usr/lib/swift$)'; then
    echo "ERROR: the app still has an rpath outside the bundle and /usr/lib/swift." >&2
    exit 1
fi

# macOS keeps the Accessibility and Microphone permissions only while the signature stays the same.
# A stable identity keeps them over rebuilds. An ad-hoc signature does not.
identity="$(security find-identity -v -p codesigning | awk -F'"' '/"/ {print $2; exit}')"
if [ -n "$identity" ]; then
    echo "Signing with: $identity"
else
    identity="-"
    echo "WARNING: no code signing identity found. Signing ad hoc."
    echo "WARNING: macOS asks for the Accessibility and Microphone permissions again after each rebuild."
fi
codesign --force --sign "$identity" --timestamp=none "$app/Contents/Frameworks/CTranscribe.framework"
for d in "$app"/Contents/Frameworks/*.dylib; do [ -e "$d" ] && codesign --force --sign "$identity" --timestamp=none "$d"; done
codesign --force --sign "$identity" --timestamp=none "$app"

echo "Built $(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
