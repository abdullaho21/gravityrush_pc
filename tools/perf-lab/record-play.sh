#!/usr/bin/env bash
# record-play.sh: records your own run so the FPS test can replay it.
#
#   tools/perf-lab/record-play.sh [name]          (default name: city1)
#
# 1. Starts the build in builds/current (APP) on a fresh copy of your settings and saves (tools/perf-lab/data-template:
#    VSync off, no frame limit, FPS overlay on). Your own saves and settings are not touched, and
#    progress made in this run is not kept.
# 2. Loads SAVEAUTO by itself. Keep your hands off the controller until a red "REC 0:00" appears
#    in the FPS overlay corner (top-right; about 10 s after Kat appears).
# 3. Play about 10 minutes through busy streets: gravity shifts, flying, landing in new places.
#    Do not open the port's own settings menu (Insert / R3+L2) while recording.
# 4. Quit the game when done (F9 stops the recording first if you want; quitting also ends it).
# Deep CPU sleep is blocked and the busiest threads pinned, as in play-fast.sh. The texture-set fix
# switches off and on every 30 s while you play (the log records which state each moment had).
# Saved: tools/perf-lab/recordings/<name>.pad (pad input by time), <name>.frames (pad input and the game's
# clock per frame, for frame-exact replays) and tools/perf-lab/results/log-rec-<name>.txt (game log).
# The controller is held neutral until REC appears (the replay starts from the same state).
# Then tools/perf-lab/replay.sh <name> replays it on its own.
set -euo pipefail
here=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
case "${1:-}" in -h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
name=${1:-city1}
[[ $name =~ ^[A-Za-z0-9_-]+$ ]] || { echo "record-play: name may use letters, digits, _ and - only" >&2; exit 1; }
app=${APP:-$here/builds/current}   # APP: an unpacked release folder
[[ -x $app/gravityrush-pc ]] || { echo "record-play: missing $app" >&2; exit 1; }
mkdir -p "$here/recordings"
rec=$here/recordings/$name.pad
if [[ -e $rec && -z ${FORCE:-} ]]; then
    echo "record-play: $rec exists; pick another name (or FORCE=1 to replace it)" >&2; exit 1
fi
echo "record-play: loading SAVEAUTO by itself; wait for the red REC mark before touching the controller"
PIN=1 TOGGLE_AB="0 12" PHASE=30 RECORD=$rec FRAME_RECORD=${rec%.pad}.frames \
    "$here/with-qos.sh" "$here/run-one.sh" "$app" "rec-$name" 10
