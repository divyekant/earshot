#!/bin/bash
# Installs the latest develop build over the installed app, and opens it again. Run it from any folder.
# Usage: update-app.sh [--no-test] [--force]
#
# 1. Gets origin/develop into a separate build worktree. Your own checkouts do not change.
# 2. Runs the release tests (--no-test skips them), then builds a staging copy with build-app.sh.
# 3. Checks the signature. The designated requirement must be the same as on the installed app.
#    Else macOS drops the Accessibility and Microphone permissions and the keychain access (Jev key).
# 4. Quits earshot, copies the build in place (previous.zip keeps the old app), and opens it again.
#
# If the installed app is already the develop commit, the script stops. --force builds and installs again.
# EARSHOT_APP sets the installed app (default: app/build/Earshot.app of this clone).
# EARSHOT_BUILD_TREE sets the build worktree (default: ~/Library/Caches/earshot/develop).
set -euo pipefail

test=1
force=0
for arg in "$@"; do
    case "$arg" in
        --no-test) test=0 ;;
        --force) force=1 ;;
        *) echo "usage: $0 [--no-test] [--force]" >&2; exit 2 ;;
    esac
done

repo="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
app="${EARSHOT_APP:-$repo/app/build/Earshot.app}"
tree="${EARSHOT_BUILD_TREE:-$HOME/Library/Caches/earshot/develop}"
stamp="$(dirname "$app")/installed-commit"
staging="$(dirname "$app")/staging/Earshot.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ ! -d "$tree" ]; then
    git -C "$repo" worktree prune
    mkdir -p "$(dirname "$tree")"
    git -C "$repo" fetch -q origin develop
    git -C "$repo" worktree add -q --detach "$tree" FETCH_HEAD
fi
git -C "$tree" fetch -q origin develop
git -C "$tree" checkout -q --detach FETCH_HEAD
commit="$(git -C "$tree" rev-parse --short HEAD)"
if [ "$force" = 0 ] && [ "$(cat "$stamp" 2>/dev/null)" = "$commit" ]; then
    echo "earshot is already on develop $commit. Use --force to install it again."
    exit 0
fi
echo "Building develop $commit: $(git -C "$tree" log -1 --format=%s)"

cd "$tree/app"
if [ "$test" = 1 ]; then nice -n 10 swift test -c release; fi
EARSHOT_APP_OUT="$staging" nice -n 10 scripts/build-app.sh

codesign --verify --deep --strict "$staging"
requirement() { codesign -d -r- "$1" 2>&1 | grep '^designated'; }
if [ -d "$app" ] && [ "$force" = 0 ] && [ "$(requirement "$staging")" != "$(requirement "$app")" ]; then
    echo "ERROR: the new build has another designated requirement. macOS would drop the permissions." >&2
    echo "The build waits at $staging. Use --force to install it anyway." >&2
    exit 1
fi

running() { pgrep -x earshot >/dev/null; }
if running; then
    echo "Quitting earshot"
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staging/Contents/Info.plist")"
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 50); do running || break; sleep 0.2; done
    if running; then pkill -TERM -x earshot || true; sleep 2; fi
    if running; then
        echo "ERROR: earshot did not quit. The build waits at $staging." >&2
        exit 1
    fi
fi

if [ -d "$app" ]; then ditto -c -k --keepParent "$app" "$(dirname "$app")/previous.zip"; fi
mkdir -p "$app"
rsync -a --delete "$staging/" "$app/"
codesign --verify --deep --strict "$app"
# The Dock and Spotlight must find only the installed copy, not the staging copy.
"$lsregister" -u "$staging" 2>/dev/null || true
rm -rf "$(dirname "$staging")"
"$lsregister" -f "$app"
echo "$commit" > "$stamp"

open "$app"
for _ in $(seq 50); do running && break; sleep 0.2; done
echo "Installed develop $commit at $app. earshot pid: $(pgrep -x earshot | paste -sd' ' -)"
