#!/usr/bin/env bash
# One A/B run: starts a build on a FRESH COPY of the user's data
# (tools/perf-lab/data-template: same settings, VSync off, no frame limit; the user's own data is never used),
# loads SAVEAUTO through scripted pad input, leaves the pad untouched, and records the
# Frame stats windows of the loaded view.
#   tools/perf-lab/run-one.sh <app-dir> <label> [settle_s] [measure_s]
# (RECORD=<file> and REPLAY=<file>: a player's recorded run and its replays, see below.)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
app=$(readlink -f "$1"); label=$2; settle=${3:-20}; secs=${4:-60}
[[ -x $app/gravityrush-pc ]] || { echo "no $app/gravityrush-pc" >&2; exit 1; }
run=$here/data-run
rm -rf "$run"; cp -a --reflink=auto "$here/data-template" "$run"
# INI="key=value ...": settings changed in the copy for this run (e.g. "stale_readback=0").
for kv in ${INI:-}; do
    k=${kv%%=*}
    if grep -q "^$k=" "$run/gravityrush.ini"; then sed -i "s|^$k=.*|$kv|" "$run/gravityrush.ini"; else echo "$kv" >> "$run/gravityrush.ini"; fi
done
pad=$here/pad.txt; : > "$pad"
log=$run/user/last_run.log
mkdir -p "$here/results"
export GRAVITYRUSH_DATA=$run GOW3_PAD_FILE=$pad
# DRAWPIPE: GOW3_DRAW_PIPE for the run (default 1; "default" leaves it unset, as a release starts).
if [[ ${DRAWPIPE:-1} == default ]]; then unset GOW3_DRAW_PIPE; else export GOW3_DRAW_PIPE=${DRAWPIPE:-1}; fi
# RECORD=<file>: the player's own run. Same load and settle as every run, then the token "record" starts
#   the pad recorder (red REC mark in the game); the run lasts until the player quits the game.
#   TOGGLE_AB keeps alternating every PHASE seconds meanwhile.
# REPLAY=<file>: plays such a recording back from the same point; the measured window is its length + 5 s.
# Both log the camera position 4 times a second with a timestamp (GOW3_CAMERA_LOG=250) for tools/perf-lab/route-compare.py.
if [[ -n ${RECORD:-} ]]; then
    RECORD=$(readlink -f "$RECORD"); export GOW3_PAD_RECORD=$RECORD GOW3_CAMERA_LOG=${CAMLOG:-250}
elif [[ -n ${REPLAY:-} ]]; then
    REPLAY=$(readlink -f "$REPLAY"); [[ -s $REPLAY ]] || { echo "$label: no recording $REPLAY" >&2; exit 1; }
    export GOW3_PAD_REPLAY=$REPLAY GOW3_CAMERA_LOG=${CAMLOG:-250}
    secs=$(( $(tail -1 "$REPLAY" | cut -d' ' -f1) / 1000 + 5 ))
fi
# FRAME_RECORD=<file> / FRAME_REPLAY=<file>: frame-exact recording and replay (pad state and the game
#   thread's clock per frame, src/runtime_pad.c), started by the same tokens. Both pin time() to
#   FIXED_TIME (default 1700000000) so the recording and its replays boot with the same value.
if [[ -n ${FRAME_RECORD:-} ]]; then
    FRAME_RECORD=$(readlink -f "$FRAME_RECORD"); export GOW3_FRAME_RECORD=$FRAME_RECORD
fi
if [[ -n ${FRAME_REPLAY:-} ]]; then
    FRAME_REPLAY=$(readlink -f "$FRAME_REPLAY"); [[ -s $FRAME_REPLAY ]] || { echo "$label: no frame recording $FRAME_REPLAY" >&2; exit 1; }
    export GOW3_FRAME_REPLAY=$FRAME_REPLAY
fi
if [[ -n ${FRAME_RECORD:-}${FRAME_REPLAY:-} ]]; then
    export GOW3_FIXED_TIME=${FIXED_TIME:-1700000000} GOW3_CAMERA_LOG=${CAMLOG:-250}
fi
# TOGGLE_AB="<word1> <word2>": same-launch A/B. The toggle file starts at "0 0" (everything on) and
# alternates with TOGGLE_AB every PHASE seconds (default 15) during the measured window.
toggles=$here/toggle.txt
echo "0 0" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"
export GOW3_TOGGLE_FILE=$toggles
# CPUSET="4-7,12-15": the whole game on those CPUs only (e.g. a smaller CPU's core count).
${CPUSET:+taskset -c "$CPUSET"} setsid "$app/gravityrush-pc" > "$here/results/console-$label.txt" 2>&1 < /dev/null &
pgid=$!
stop() { kill -TERM -- "-$pgid" 2>/dev/null || true; sleep 3; kill -KILL -- "-$pgid" 2>/dev/null || true; wait "$pgid" 2>/dev/null || true; }
trap stop EXIT
tap() { echo "$1" > "$pad"; sleep 0.25; : > "$pad"; sleep "${2:-1.2}"; }
# Title -> Load game -> SAVEAUTO: tap cross until the runtime logs the chosen save.
t0=$SECONDS
until grep -q 'chose SAVEAUTO' "$log" 2>/dev/null; do
    (( SECONDS - t0 < 150 )) || { echo "$label: FAILED, no save chosen in 150 s"; exit 1; }
    kill -0 "$pgid" 2>/dev/null || { echo "$label: FAILED, game exited"; exit 1; }
    tap cross
done
: > "$pad"
# Loaded: wait for gameplay windows (more than 500 draws/frame), then settle.
t1=$SECONDS
until grep -n 'Frame stats' "$log" | awk -v t="$(grep -n 'chose SAVEAUTO' "$log" | head -1 | cut -d: -f1)" -F: '$1>t' |
      grep -qE ' ([5-9][0-9]{2}|[0-9]{4,}) draws/frame'; do
    (( SECONDS - t1 < 120 )) || { echo "$label: FAILED, no gameplay view in 120 s"; exit 1; }
    sleep 1
done
if [[ -n ${PIN:-} ]]; then
    # PIN=1: the four busiest threads get a physical core each (tools/perf-lab/pin-threads.sh).
    pid=$(ps -o pid=,comm= -g "$pgid" | awk '$2 ~ /^gravityrush-r/ {print $1; exit}')
    [[ -n $pid ]] || { echo "$label: FAILED, runtime process not found in group $pgid"; exit 1; }
    "$here/pin-threads.sh" "$pid" > "$here/results/pin-$label.txt" 2>&1
    (( $(grep -cE 'pinned (shadPS4:GpuComm|gow3:DrawRec|gow3:VkRecorder|DrawThread) ' "$here/results/pin-$label.txt") >= 4 )) ||
        echo "$label: pinning incomplete: $(tail -1 "$here/results/pin-$label.txt")"
fi
if [[ -n ${MON:-} ]]; then
    # MON=1: once a second, the game's threads, every CPU, the busiest other processes and the GPU
    # (monitor.py) into results/mon-<label>.jsonl until the game exits.
    mpid=$(ps -o pid=,comm= -g "$pgid" | awk '$2 ~ /^gravityrush-r/ {print $1; exit}')
    [[ -n $mpid ]] && python3 "$here/monitor.py" "$mpid" "$here/results/mon-$label.jsonl" &
fi
if [[ -n ${PAD_HOLD:-} ]]; then
    # PAD_HOLD="rx=255" etc.: held from here to the end (e.g. the camera keeps turning).
    echo "$PAD_HOLD" > "$pad"
fi
sleep "$settle"
if [[ -n ${SHOT:-} ]]; then
    # SHOT=1: one screenshot of the screen (the game is fullscreen) at the start of the measured window.
    # Only the game window's own area (Hyprland: the window with the game's process), never the
    # rest of the desktop; no screenshot when the window cannot be found.
    gpid=$(ps -o pid=,comm= -g "$pgid" | awk '$2 ~ /^gravityrush-r/ {print $1; exit}')
    geom=$(hyprctl clients -j 2>/dev/null | python3 -c 'import json,sys
p=int(sys.argv[1]); c=[c for c in json.load(sys.stdin) if c.get("pid")==p]
print("%d,%d %dx%d" % (*c[0]["at"], *c[0]["size"]) if c else "")' "${gpid:-0}" 2>/dev/null)
    if [[ -n $geom ]]; then
        grim -g "$geom" "$here/results/shot-$label.png" 2>"$here/results/shot-$label.err" || echo "$label: screenshot failed"
    else
        echo "$label: game window not found, no screenshot"
    fi
fi
start=$(wc -l < "$log")
if [[ -n ${SAMPLETHREADS:-} ]]; then
    # SAMPLETHREADS="DrawThread shadPS4:GpuComm": for SAMPLESECS (default 20) of the measured window, the
    # state and system call of each of those threads ~1000 times a second (syscall-sample.py).
    spid=$(ps -o pid=,comm= -g "$pgid" | awk '$2 ~ /^gravityrush-r/ {print $1; exit}')
    for sname in $SAMPLETHREADS; do
        taskset -c "${SAMPLECPU:-15}" python3 "$here/syscall-sample.py" "$spid" "$sname" "${SAMPLESECS:-20}" \
            "$here/results/sys-$label-${sname//[^A-Za-z0-9]/_}.json" &
    done
fi
if [[ -n ${PERFTHREAD:-} ]]; then
    # PERFTHREAD=<thread name>: during the measured window, perf stat (cycles, instructions, TLB misses)
    # and perf record (user space) of that one thread of the game, into results/perf*-<label>.*.
    ppid=$(ps -o pid=,comm= -g "$pgid" | awk '$2 ~ /^gravityrush-r/ {print $1; exit}')
    ptid=$(for t in /proc/"$ppid"/task/*; do [[ $(<"$t/comm") == "$PERFTHREAD" ]] && { echo "${t##*/}"; break; }; done)
    if [[ -n $ptid ]]; then
        pdur=${PERFSECS:-20}
        perf stat -t "$ptid" -x, -o "$here/results/perfstat-$label.csv" \
            -e cycles:u,instructions:u,dTLB-load-misses:u,iTLB-load-misses:u -- sleep "$pdur" 2>/dev/null &
        perf record -q -t "$ptid" -e cycles:u -F 1999 -o "$here/results/perfrec-$label.data" -- sleep "$pdur" \
            2>"$here/results/perfrec-$label.err" &
    else
        echo "$label: no thread named $PERFTHREAD"
    fi
fi
now_ms() { echo $(( ${EPOCHREALTIME//[.,]/} / 1000 )); }
# TOGGLE_AB phases on a fixed clock from the start of the measured window (no drift over long runs):
# phase k is "0 0" (everything on) or TOGGLE_AB; INVERT=1 starts with TOGGLE_AB (replays then measure
# each stretch of a route both ways).
set_phase() {
    local w="0 0"; (( ($1 + ${INVERT:-0}) % 2 )) && w=$TOGGLE_AB
    echo "$w" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"
}
# toggle_until <ms>: alternate (if TOGGLE_AB is set) until that much time has passed or the game is gone.
toggle_until() {
    local t0 k=-1 el phase_ms=$(( ${PHASE:-15} * 1000 )); t0=$(now_ms)
    while kill -0 -- "-$pgid" 2>/dev/null; do
        el=$(( $(now_ms) - t0 )); (( el < $1 )) || break
        if [[ -n ${TOGGLE_AB:-} ]] && (( el / phase_ms != k )); then k=$(( el / phase_ms )); set_phase "$k"; fi
        sleep 0.25
    done
    [[ -z ${TOGGLE_AB:-} ]] || { echo "0 0" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"; }
    echo $(( ($(now_ms) - t0) / 1000 ))
}
tok=""
[[ -n ${RECORD:-}${FRAME_RECORD:-} ]] && tok+=" record"
[[ -n ${REPLAY:-}${FRAME_REPLAY:-} ]] && tok+=" replay"
[[ -z $tok ]] || echo "$tok" > "$pad"
if [[ -n ${RECORD:-} ]]; then
    echo "$label: recording; play, then quit the game (F9 stops the recording early)"
    t=$(toggle_until 999999999)
    echo "$label: game closed after ${t} s; $(wc -l < "$RECORD") pad changes in $RECORD"
elif [[ -n ${FRAME_REPLAY:-} ]]; then
    # Until the runtime reports the end of the frame replay (it renders at its own speed), at most 3x the
    # recorded game time + 2 min; TOGGLE_AB alternates by wall clock meanwhile.
    limit=$(( $(tail -1 "$FRAME_REPLAY" | awk '{print int($13 / 1000000)}') * 3000 + 120000 ))
    ( toggle_until "$limit" > /dev/null ) & flipper=$!
    t0=$SECONDS
    until grep -q 'frame replay finished' "$log" 2>/dev/null; do
        kill -0 -- "-$pgid" 2>/dev/null || { echo "$label: game exited during the frame replay"; break; }
        (( (SECONDS - t0) * 1000 < limit )) || { echo "$label: frame replay did not finish in time"; break; }
        sleep 1
    done
    sleep 5
    kill "$flipper" 2>/dev/null || true; wait "$flipper" 2>/dev/null || true
    echo "0 0" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"
    grep -h 'frame replay finished' "$log" | sed "s/^/$label: /"
elif [[ -n ${REPLAY:-} ]]; then
    toggle_until $(( secs * 1000 )) > /dev/null
elif [[ -n ${PERF:-} ]]; then
    # PERF=1: sample the runtime process (user space, every thread) during the measured window.
    pid=$(ps -o pid=,comm= -g "$pgid" | awk '$2 ~ /^gravityrush-r/ {print $1; exit}')
    [[ -n $pid ]] || { echo "$label: FAILED, runtime process not found in group $pgid"; exit 1; }
    perf record -q -e cycles:u -F 999 -p "$pid" -o "$here/results/perf-$label.data" -- sleep "$secs" 2>"$here/results/perf-$label.err" ||
        echo "$label: perf record failed (see results/perf-$label.err)"
elif [[ -n ${PIN_AB:-} ]]; then
    # PIN_AB=1 (with PIN=1): the pinning layouts in PIN_LAYOUTS (default "1 3 4") take turns every PHASE
    # seconds in this launch. Unused toggle bits mark the layout in the game's log for tools/perf-lab/toggle-summary.py:
    # layout 1 "0", layout 3 bit 62, layout 4 bit 63 (no switch reads either bit).
    phase=${PHASE:-15}
    read -r -a layouts <<< "${PIN_LAYOUTS:-1 3 4}"
    declare -A marker=([1]=0 [3]=4611686018427387904 [4]=9223372036854775808)
    i=0
    for (( t = 0; t < secs; t += phase )); do
        l=${layouts[i % ${#layouts[@]}]}; i=$((i + 1))
        LAYOUT=$l "$here/pin-threads.sh" "$pid" >> "$here/results/pin-$label.txt" 2>&1
        echo "${marker[$l]} 0" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"
        sleep "$phase"
    done
    LAYOUT=1 "$here/pin-threads.sh" "$pid" >> "$here/results/pin-$label.txt" 2>&1
    echo "0 0" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"
elif [[ -n ${TOGGLE_AB:-} ]]; then
    # INVERT=1: start with TOGGLE_AB instead of "0 0" (replays measure each stretch of a route both ways).
    phase=${PHASE:-15}
    for (( t = 0; t < secs; t += phase )); do
        if (( (t / phase + ${INVERT:-0}) % 2 )); then echo "$TOGGLE_AB" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"; else echo "0 0" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"; fi
        sleep "$phase"
    done
    echo "0 0" > "$toggles.tmp" && mv -f "$toggles.tmp" "$toggles"
else
    sleep "$secs"
fi
end=$(wc -l < "$log")
sed -n "$((start + 1)),${end}p" "$log" > "$here/results/window-$label.txt"
cp "$log" "$here/results/log-$label.txt"
python3 - "$here/results/window-$label.txt" "$label" <<'EOF'
import re, statistics as st, sys
text = open(sys.argv[1]).read()
fps = [float(x) for x in re.findall(r'^Frame stats: ([\d.]+) FPS', text, re.M)]
us = [float(x) for x in re.findall(r'GPU thread ([\d.]+) us/draw', text)]
dpf = [float(x) for x in re.findall(r'(\d+) draws/frame', text)]
p99 = [float(x) for x in re.findall(r'^Frame pacing: .*p99 ([\d.]+) ms', text, re.M)]
pipe = [float(x) for x in re.findall(r'^Draw pipe: (\d+) draws/s', text, re.M)]
m = lambda v: f"{st.mean(v):.2f}" if v else "n/a"
print(f"{sys.argv[2]}: windows {len(fps)}  FPS {m(fps)} (min {min(fps) if fps else 'n/a'}, max {max(fps) if fps else 'n/a'})  "
      f"us/draw {m(us)}  draws/frame {m(dpf)}  FPSxdraws {st.mean(f*d for f, d in zip(fps, dpf))/1000:.1f}k/s  "
      f"pacing p99 {m(p99)} ms  pipe draws/s {m(pipe)}")
EOF
