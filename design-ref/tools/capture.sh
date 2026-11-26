#!/bin/bash
# Records the bottom-center of the screen while driving one dictation:
# press hotkey -> play a fixed spoken phrase through the speakers -> press hotkey -> wait.
#
#   capture.sh <clip-name> <right-option|right-command> [seconds=14]
#
# Output: design-ref/clips/<clip-name>.mov and <clip-name>.events (seconds from capture start).
# The transcript gets pasted into a blank TextEdit document opened for that purpose.
set -euo pipefail

TOOLS="$(cd "$(dirname "$0")" && pwd)"
CLIPS="${CLIPS:-$HOME/Downloads/VoiceInk-UI-Polish/2-clips}"  # clips + events (kept)
WORK="$TOOLS/../clips"                                         # scratch: phrase audio, paste target
mkdir -p "$CLIPS" "$WORK"

NAME="$1"
KEY="$2"
SECONDS_TOTAL="${3:-20}"
PHRASE="${PHRASE:-喂喂喂，你好呀，测试测试，嗨呀。}"
VOICE="${VOICE:-Tingting}"

# Region: 560x200 pt centered horizontally, bottom edge 20 pt below the top of the Dock.
read -r RX RY RW RH < <(osascript -l JavaScript -e '
ObjC.import("AppKit");
const s = $.NSScreen.screens.objectAtIndex(0); const f = s.frame, v = s.visibleFrame;
const w = 560, h = 200;
const x = Math.round(f.size.width / 2 - w / 2);
const bottom = Math.round(f.size.height - v.origin.y + 20);
`${x} ${bottom - h} ${w} ${h}`')

# SPEAKER=human: the user reads the phrase while the recorder is open (no speech playback).
SPEAKER="${SPEAKER:-tts}"
SPEAK_SECONDS="${SPEAK_SECONDS:-13}"

if [ "$SPEAKER" = "tts" ]; then
    # Loud enough for the built-in mic to pick up; restored on exit.
    OLD_VOLUME=$(osascript -e 'output volume of (get volume settings)')
    trap 'osascript -e "set volume output volume $OLD_VOLUME" >/dev/null' EXIT
    osascript -e "set volume output volume ${CAPTURE_VOLUME:-60}" >/dev/null

    PHRASE_FILE="$WORK/.phrase-$VOICE.aiff"
    [ -f "$PHRASE_FILE" ] || say -v "$VOICE" -o "$PHRASE_FILE" "$PHRASE"
fi

# Blank plain-text paste target (no format bar or ruler) filling the capture region, so every run
# has the same backdrop and the pasted transcript shows up in the top ~35 pt of the clip.
PASTE_TARGET="$WORK/.paste-target.txt"
: > "$PASTE_TARGET"
osascript \
    -e "tell application \"TextEdit\" to open POSIX file \"$PASTE_TARGET\"" \
    -e 'tell application "TextEdit" to activate' \
    -e "tell application \"TextEdit\" to set bounds of (first window whose name is \".paste-target.txt\") to {$RX, $((RY - 28)), $((RX + RW)), $((RY + RH))}" \
    >/dev/null
# Only the paste target is moved or closed, never another TextEdit document that happens to be open.
sleep 0.8

EVENTS="$CLIPS/$NAME.events"
: > "$EVENTS"
T0=$(python3 -I -c 'import time; print(time.time())')
stamp() { python3 -I -c "import time; print(f'{time.time()-$T0:.2f} $1')" >> "$EVENTS"; }

rm -f "$CLIPS/$NAME.mov"  # screencapture refuses to overwrite an existing file
screencapture -x -V "$SECONDS_TOTAL" -R"$RX,$RY,$RW,$RH" "$CLIPS/$NAME.mov" &
CAP=$!
stamp capture-start
sleep 1.5

"$TOOLS/press" "$KEY" 0.08; stamp hotkey-start
if [ "$SPEAKER" = "human" ]; then
    sleep "$SPEAK_SECONDS"
else
    sleep 0.8
    stamp speech-start; afplay "$PHRASE_FILE"; stamp speech-end
    sleep 1.2
fi
"$TOOLS/press" "$KEY" 0.08; stamp hotkey-stop

wait "$CAP" || true
stamp capture-end
osascript -e 'tell application "TextEdit" to close (every document whose name is ".paste-target.txt") saving no' >/dev/null 2>&1 || true

echo "clip:   $CLIPS/$NAME.mov"
echo "region: $RX,$RY ${RW}x$RH"
cat "$EVENTS"
