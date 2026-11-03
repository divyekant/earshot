#!/bin/bash
# Updates the installed app to the tip of origin/develop, with no clicks. Run it from any folder.
# Usage: update-app.sh [--dry-run] [--force] [--skip-tests] [--now]
#
#   --dry-run     Fetch develop, compare it with the installed app, and print the next steps. Change nothing.
#   --force       Build and install also when the installed app has the same commit.
#   --skip-tests  Do not run the release tests.
#   --now         Do not wait until earshot is idle.
#
# EARSHOT_APP sets the installed app (default: app/build/Earshot.app of this clone).
# EARSHOT_BUILD_TREE sets the build worktree (default: ~/Library/Caches/earshot/develop).
# The log goes to ~/Library/Logs/earshot-mem/update-<UTC time>.log.
#
# The script builds in a separate worktree, so your own checkout does not change. It never builds
# a feature branch. If a step fails before the quit, earshot and the installed app stay as they are.
# If a step fails after the quit, the script puts back the old app from the zip backup and opens it.
# It does not touch the settings, the voice profile or the Keychain.
set -euo pipefail

dry=0 force=0 tests=1 wait_idle=1
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry=1 ;;
        --force) force=1 ;;
        --skip-tests) tests=0 ;;
        --now) wait_idle=0 ;;
        *) echo "usage: $0 [--dry-run] [--force] [--skip-tests] [--now]" >&2; exit 2 ;;
    esac
done

repo="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
app="${EARSHOT_APP:-$repo/app/build/Earshot.app}"
builds="$(dirname "$app")"
tree="${EARSHOT_BUILD_TREE:-$HOME/Library/Caches/earshot/develop}"
activity="$HOME/Library/Application Support/earshot/activity.jsonl"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
logs="$HOME/Library/Logs/earshot-mem"
if [ "$dry" = 1 ]; then log_file=/dev/null; else mkdir -p "$logs"; log_file="$logs/update-$(date -u +%Y%m%d-%H%M%SZ).log"; fi

old="unknown" new="unknown" test_result="not run" quit_done=0 backup=""

log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$log_file"; }
plan() { log "dry run: would $*"; }
result() { log "RESULT: $1. old ${old:0:7}, new ${new:0:7}, tests $test_result, pid ${2:-none}. Log: $log_file"; }
pids() { pgrep -x earshot || true; }
running() { [ -n "$(pids)" ]; }

rollback() {
    [ -n "$backup" ] || { log "No backup to put back."; return; }
    log "Putting back the old app from $backup"
    osascript -e "quit app id \"$bundle_id\"" >/dev/null 2>&1 || true
    for _ in $(seq 75); do running || break; sleep 0.2; done
    local restore="$builds/restore-$$"
    mkdir -p "$restore"
    ditto -x -k "$backup" "$restore"
    rsync -a --delete "$restore/Earshot.app/" "$app/"
    rm -rf "$restore"
    "$lsregister" -f "$app"
    open "$app"
    log "Opened the old app again."
}

fail() {
    trap - ERR
    log "FAILED: $*"
    if [ "$quit_done" = 1 ]; then rollback || log "The rollback failed. Unzip $backup by hand."; fi
    result "failed" "$(pids | paste -sd' ' -)"
    exit 1
}
trap 'fail "line $LINENO: a command failed"' ERR

# 1. Source: the tip of origin/develop.
git -C "$repo" fetch -q origin develop
new="$(git -C "$repo" rev-parse origin/develop)"
log "develop is ${new:0:7}: $(git -C "$repo" log -1 --format=%s "$new")"
if [ -d "$tree" ] && [ -n "$(git -C "$tree" status --porcelain)" ]; then
    fail "the build worktree $tree has changes. Clean it or remove it."
fi

# 2. Up-to-date check.
if [ -f "$app/Contents/Info.plist" ]; then
    old="$(/usr/libexec/PlistBuddy -c 'Print :EarshotCommit' "$app/Contents/Info.plist" 2>/dev/null || echo unknown)"
fi
log "installed app $app has commit $old"
if [ "$old" = "$new" ] && [ "$force" = 0 ]; then
    log "up to date"
    result "up to date" "$(pids | paste -sd' ' -)"
    exit 0
fi

staging="$builds/staging-${new:0:7}/Earshot.app"
if [ "$dry" = 1 ]; then
    plan "check out ${new:0:7} in $tree"
    if [ "$tests" = 1 ]; then plan "run: nice -n 10 swift test -c release -Xswiftc -enable-testing"; fi
    plan "build $staging with build-app.sh, then check the signature, the designated requirement, AppIcon, CTranscribe and the rpaths"
    if [ "$wait_idle" = 1 ]; then plan "wait until $activity is 2 minutes old (at most 10 minutes)"; fi
    if running; then plan "quit earshot (pid $(pids | paste -sd' ' -))"; fi
    plan "zip $app to $builds/old-<time>.zip and keep the newest 3 zips"
    plan "copy the staging build into $app, unregister the staging copy, and open $app"
    result "dry run, no changes" "$(pids | paste -sd' ' -)"
    exit 0
fi

if [ ! -d "$tree" ]; then
    log "Making the build worktree $tree"
    git -C "$repo" worktree prune
    mkdir -p "$(dirname "$tree")"
    git -C "$repo" worktree add -q --detach "$tree" "$new"
fi
git -C "$tree" checkout -q --detach "$new"

# 3. Tests, as in CI.
if [ "$tests" = 1 ]; then
    log "Running the release tests"
    (cd "$tree/app" && nice -n 10 swift test -c release -Xswiftc -enable-testing) >>"$log_file" 2>&1 \
        || fail "a test failed. See the log."
    test_result="passed"
else
    test_result="skipped"
fi

# 4. Staging build and checks.
log "Building $staging"
EARSHOT_APP_OUT="$staging" nice -n 10 "$tree/app/scripts/build-app.sh" >>"$log_file" 2>&1 || fail "the build failed. See the log."
codesign --verify --deep --strict "$staging" || fail "the signature of the staging build is not valid"
requirement() { codesign -d -r- "$1" 2>&1 | grep '^designated'; }
if [ -d "$app" ] && [ "$(requirement "$staging")" != "$(requirement "$app")" ]; then
    fail "the designated requirement changed. macOS would drop the Accessibility and Microphone permissions."
fi
[ -f "$staging/Contents/Resources/AppIcon.icns" ] || fail "AppIcon.icns is missing"
want="$(grep -o 'transcribe.cpp/releases/download/v[0-9.]*' "$tree/app/Package.swift" | sed 's/.*v//')"
strings "$staging/Contents/Frameworks/CTranscribe.framework/CTranscribe" | grep -x "$want" >/dev/null \
    || fail "CTranscribe is not version $want"
if otool -l "$staging/Contents/MacOS/earshot" | awk '$1 == "path"' | grep -Ev 'path (@|/usr/lib/swift )'; then
    fail "the app has an rpath outside the bundle and /usr/lib/swift"
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staging/Contents/Info.plist")"
log "Checks passed: signature, designated requirement, AppIcon, CTranscribe $want, rpaths"

# 5. Idle guard: do not quit in the middle of a turn or a test.
if [ "$wait_idle" = 1 ] && running && [ -f "$activity" ]; then
    for i in $(seq 0 60); do
        age=$(( $(date +%s) - $(stat -f %m "$activity") ))
        [ "$age" -ge 120 ] && break
        [ "$i" = 60 ] && fail "earshot is in use (last activity ${age} s ago). Run the script again later, or use --now."
        [ "$i" = 0 ] && log "earshot was used ${age} s ago. Waiting until it is idle for 2 minutes."
        sleep 10
    done
fi

# 6. Quit earshot gracefully.
if running; then
    log "Quitting earshot (pid $(pids | paste -sd' ' -))"
    osascript -e "quit app id \"$bundle_id\"" >/dev/null 2>&1 || true
    for _ in $(seq 75); do running || break; sleep 0.2; done
    running && fail "earshot did not quit in 15 s. It still runs. Nothing changed."
fi

# 7. Backup and install.
if [ -d "$app" ]; then
    backup="$builds/old-$(date +%Y%m%d-%H%M%S).zip"
    ditto -c -k --keepParent "$app" "$backup"
    unzip -l "$backup" Earshot.app/Contents/Info.plist >/dev/null || fail "the backup $backup is not complete"
    log "Backup: $backup ($(unzip -l "$backup" | tail -1 | awk '{print $2}') files)"
    # shellcheck disable=SC2012
    ls -1t "$builds"/old-*.zip | tail -n +4 | while read -r f; do rm -f "$f"; done
fi
quit_done=1
mkdir -p "$app"
rsync -a --delete "$staging/" "$app/"
codesign --verify --deep --strict "$app" || fail "the signature of the installed app is not valid"
cmp -s "$staging/Contents/Info.plist" "$app/Contents/Info.plist" || fail "Info.plist was not copied"

# 8. Only the installed copy can open.
rm -rf "$staging-disabled"
mv "$staging" "$staging-disabled"
"$lsregister" -u "$staging" 2>/dev/null || true
"$lsregister" -f "$app"
# shellcheck disable=SC2012
ls -1dt "$builds"/staging-* | tail -n +4 | while read -r d; do rm -rf "$d"; done

# 9. Open the new build and check it.
open "$app"
pid=""
for _ in $(seq 75); do
    list="$(pids)"
    if [ "$(echo "$list" | grep -c .)" = 1 ] && [ "$(ps -o comm= -p "$list")" = "$app/Contents/MacOS/earshot" ]; then
        pid="$list"
        break
    fi
    sleep 0.2
done
[ -n "$pid" ] || fail "the new build did not start as one process from $app"
sleep 3
kill -0 "$pid" 2>/dev/null || fail "the new build stopped after the start"
result "updated" "$pid"
