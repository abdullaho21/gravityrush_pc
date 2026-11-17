#!/usr/bin/env bash
# replay.sh: replays a recorded run (tools/perf-lab/record-play.sh) as an automated FPS test.
#
#   tools/perf-lab/replay.sh [name] [runs]        (defaults: city1, 2)
#
# Each run: the same build, fresh data copy, load and settle as the recording, then the recorded pad
# input from the same point; deep sleep blocked and threads pinned. The texture-set fix alternates
# every 30 s; odd runs start with it off, even runs with it on (like the recording), so every 30-s
# stretch of the route is measured both ways. Hands off the controller while it runs (a replay
# overrides the pad, but the keyboard's F9 and the settings menu still work).
# Afterwards tools/perf-lab/replay-report.py compares each route with the recorded one and the fix on/off.
set -euo pipefail
here=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
case "${1:-}" in -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
name=${1:-city1}; runs=${2:-2}
app=${APP:-$here/builds/current}   # APP: an unpacked release folder
rec=$here/recordings/$name.pad
[[ -s $rec ]] || { echo "replay: no recording $rec" >&2; exit 1; }
[[ -x $app/gravityrush-pc ]] || { echo "replay: missing $app" >&2; exit 1; }
logs=()
for (( i = 1; i <= runs; i++ )); do
    label=replay-$name-$i
    # Frame-exact when the recording has its .frames file (pad input and game clock per frame),
    # else timed by the wall clock. Both drift from the route after a while (README).
    if [[ -s ${rec%.pad}.frames ]]; then mode=(FRAME_REPLAY="${rec%.pad}.frames"); else mode=(REPLAY="$rec"); fi
    env PIN=1 TOGGLE_AB="0 12" PHASE=30 INVERT=$(( i % 2 )) "${mode[@]}" \
        "$here/with-qos.sh" "$here/run-one.sh" "$app" "$label" 10
    logs+=("$here/results/log-$label.txt")
done
python3 "$here/replay-report.py" --phase 30 "$here/results/log-rec-$name.txt" "${logs[@]}" |
    tee "$here/results/replay-report-$name.txt"
