#!/bin/bash
# Builds the Footnote plugin and copies it to the plugins folder of earshot (docs/PLUGINS.md, section 2).
#
# The script:
#   1. builds the program with the release configuration,
#   2. puts it in the app bundle Footnote.app, with Info.plist,
#   3. signs the bundle with the first code signing identity (ad hoc only if none exists),
#   4. copies the bundle and plugin.json to ~/Library/Application Support/earshot/plugins/footnote/,
#   5. downloads the search model to the data folder of Footnote, at a fixed revision with a SHA-256 check
#      (scripts/get-model.sh). The The Footnote program has no network code.
#
# The script does not touch the approval file (plugins-approved.json) and does not restart earshot.
# The owner approves the plugin in Manage > Plugins. If plugin.json did not change, the approval stays.
#
# macOS keeps the Reminders permission only while the signature stays the same. A stable identity keeps it over
# rebuilds. An ad hoc signature does not.
#
# Environment:
#   FOOTNOTE_PLUGINS_DIR  the plugins folder (default: ~/Library/Application Support/earshot/plugins)
#   FOOTNOTE_NO_INSTALL=1 build and sign only. The bundle stays in .build/Footnote.app.
#   FOOTNOTE_DATA_DIR     the data folder of Footnote (default: ~/Library/Application Support/earshot/plugin-data/footnote)
#   FOOTNOTE_MODEL        the search model: gemma (default), qwen3 or none (keywords only). It must agree with
#                   "searchModel" in settings.json of Footnote.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

swift build -c release --product footnote
bin="$(swift build -c release --show-bin-path)/footnote"

app="$here/.build/Footnote.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/footnote"
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
codesign --force --sign "$identity" --identifier com.divyekant.earshot.footnote --timestamp=none "$app"
codesign --verify --strict "$app"

if [ "${FOOTNOTE_NO_INSTALL:-0}" = "1" ]; then
    echo "Built: $app"
    exit 0
fi

plugins="${FOOTNOTE_PLUGINS_DIR:-$HOME/Library/Application Support/earshot/plugins}"
dest="$plugins/footnote"
mkdir -p "$dest"
# Copy to a new folder, then swap, so that earshot never starts a half-copied program.
tmp="$(mktemp -d "$plugins/.footnote-install.XXXXXX")"
cp -R "$app" "$tmp/Footnote.app"
rm -rf "$dest/Footnote.app"
mv "$tmp/Footnote.app" "$dest/Footnote.app"
rmdir "$tmp"
if ! cmp -s "$here/plugin.json" "$dest/plugin.json"; then
    cp "$here/plugin.json" "$dest/plugin.json"
    echo "plugin.json is new or changed. Approve the plugin in Manage > Plugins."
fi
echo "Installed: $dest"

model="${FOOTNOTE_MODEL:-gemma}"
if [ "$model" != "none" ]; then
    data="${FOOTNOTE_DATA_DIR:-$HOME/Library/Application Support/earshot/plugin-data/footnote}"
    # Footnote had the name "PA" before 2026-11-15. If only the old data folder exists, put the model there:
    # earshot moves the old folder to the new name at the next "Read again" (docs/PLUGINS.md 2.1).
    old="$HOME/Library/Application Support/earshot/plugin-data/pa"
    if [ -z "${FOOTNOTE_DATA_DIR:-}" ] && [ ! -d "$data" ] && [ -d "$old" ]; then
        data="$old"
    fi
    "$here/scripts/get-model.sh" "$model" "$data/models"
fi
echo "Click \"Read again\" in Manage > Plugins, or run: earshot plugins reload. If an older earshot keeps the old program, turn Approved off and on for Footnote."
