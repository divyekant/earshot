#!/bin/bash
# Builds the PA plugin and copies it to the plugins folder of earshot (docs/PLUGINS.md, section 2).
#
# The script:
#   1. builds the program with the release configuration,
#   2. puts it in the app bundle EarshotPA.app, with Info.plist,
#   3. signs the bundle with the first code signing identity (ad hoc only if none exists),
#   4. copies the bundle and plugin.json to ~/Library/Application Support/earshot/plugins/pa/,
#   5. downloads the search model to the data folder of the PA, at a fixed revision with a SHA-256 check
#      (scripts/get-model.sh). The PA program has no network code.
#
# The script does not touch the approval file (plugins-approved.json) and does not restart earshot.
# The owner approves the plugin in Manage > Plugins. If plugin.json did not change, the approval stays.
#
# macOS keeps the Reminders permission only while the signature stays the same. A stable identity keeps it over
# rebuilds. An ad hoc signature does not.
#
# Environment:
#   PA_PLUGINS_DIR  the plugins folder (default: ~/Library/Application Support/earshot/plugins)
#   PA_NO_INSTALL=1 build and sign only. The bundle stays in .build/EarshotPA.app.
#   PA_DATA_DIR     the data folder of the PA (default: ~/Library/Application Support/earshot/plugin-data/pa)
#   PA_MODEL        the search model: gemma (default), qwen3 or none (keywords only). It must agree with
#                   "searchModel" in settings.json of the PA.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

swift build -c release --product earshot-pa
bin="$(swift build -c release --show-bin-path)/earshot-pa"

app="$here/.build/EarshotPA.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/earshot-pa"
cp "$here/Info.plist" "$app/Contents/Info.plist"
# The model runtime (llama.cpp). SwiftPM puts the framework next to the program.
framework="$(dirname "$bin")/llama.framework"
if [ -d "$framework" ]; then
    mkdir -p "$app/Contents/Frameworks"
    ditto "$framework" "$app/Contents/Frameworks/llama.framework"
fi

identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/ {print $2; exit}')"
if [ -n "$identity" ]; then
    echo "Signing with: $identity"
else
    identity="-"
    echo "WARNING: no code signing identity found. Signing ad hoc. macOS can ask for Reminders again after each build."
fi
if [ -d "$app/Contents/Frameworks/llama.framework" ]; then
    codesign --force --sign "$identity" --timestamp=none "$app/Contents/Frameworks/llama.framework"
fi
codesign --force --sign "$identity" --identifier com.divyekant.earshot.pa --timestamp=none "$app"
codesign --verify --strict "$app"

if [ "${PA_NO_INSTALL:-0}" = "1" ]; then
    echo "Built: $app"
    exit 0
fi

plugins="${PA_PLUGINS_DIR:-$HOME/Library/Application Support/earshot/plugins}"
dest="$plugins/pa"
mkdir -p "$dest"
# Copy to a new folder, then swap, so that earshot never starts a half-copied program.
tmp="$(mktemp -d "$plugins/.pa-install.XXXXXX")"
cp -R "$app" "$tmp/EarshotPA.app"
rm -rf "$dest/EarshotPA.app"
mv "$tmp/EarshotPA.app" "$dest/EarshotPA.app"
rmdir "$tmp"
if ! cmp -s "$here/plugin.json" "$dest/plugin.json"; then
    cp "$here/plugin.json" "$dest/plugin.json"
    echo "plugin.json is new or changed. Approve the plugin in Manage > Plugins."
fi
echo "Installed: $dest"

model="${PA_MODEL:-gemma}"
if [ "$model" != "none" ]; then
    data="${PA_DATA_DIR:-$HOME/Library/Application Support/earshot/plugin-data/pa}"
    "$here/scripts/get-model.sh" "$model" "$data/models"
fi
echo "Click \"Read again\" in Manage > Plugins. If an older earshot keeps the old program, turn Approved off and on for PA."
