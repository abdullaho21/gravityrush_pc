#!/usr/bin/env bash
# play-fast.sh — Gravity Rush Remastered, the fastest setup measured on a Ryzen 7 7800X3D + RX 9070 XT.
#
#   play-fast.sh [GAME_FOLDER] [runtime arguments...]
#
# 1. The build in builds/current (or PLAY_FAST_APP): an unpacked release folder. Measured with a PGO
#    build (GOW3_PGO=use packaging/linux/build-release.sh, profile from train-pgo.sh).
# 2. Deep CPU sleep blocked while the game runs: a /dev/cpu_dma_latency request of 20 us (needs write
#    access, e.g. group audio on some distributions). It is released as soon as this script ends.
# 3. The four busiest threads (GPU commands, draw recording, Vulkan recording, the game's DrawThread) get
#    a physical core each (CPUs 0-3); every other thread of the game runs on cores 4-7 (CPUs 4-7, 12-15).
#    Only for this game process, re-checked every 2 s (threads that appear later, the in-game restart).
#    Layout for an 8-core CPU with SMT where CPU n and n+8 share a core (Ryzen 7 7800X3D); skipped elsewhere.
# Uses your normal settings, saves and game folder (~/.local/share/gravityrush-pc), draw pipe on.
# Measured (SAVEAUTO view, uncapped): 303 FPS vs 251 for the 0.1.15-2 release setup. Busy streets unchecked.
# Off switches: PLAY_FAST_NO_HOLD=1, PLAY_FAST_NO_PIN=1 (for comparisons).
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
app="${PLAY_FAST_APP:-$here/builds/current}"   # PLAY_FAST_APP: an unpacked release folder
[[ -x $app/gravityrush-pc ]] || { echo "play-fast: missing $app" >&2; exit 1; }
case "${1:-}" in -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
export GOW3_DRAW_PIPE="${GOW3_DRAW_PIPE:-1}"
note="$here/play-fast.log"
: > "$note"
say() { echo "play-fast: $*" | tee -a "$note"; }

if [[ -z ${PLAY_FAST_NO_HOLD:-} && -w /dev/cpu_dma_latency ]]; then
    exec 3>/dev/cpu_dma_latency
    python3 -c 'import struct,sys; sys.stdout.buffer.write(struct.pack("i", 20))' >&3
    say "deep CPU sleep blocked while the game runs (cpu_dma_latency 20 us)"
else
    say "deep CPU sleep NOT blocked (switched off or /dev/cpu_dma_latency not writable)"
fi

pin=1
if [[ -n ${PLAY_FAST_NO_PIN:-} ]]; then pin=0; say "thread pinning switched off";
elif [[ $(nproc) != 16 || $(</sys/devices/system/cpu/cpu0/topology/thread_siblings_list) != 0,8 ||
        $(</sys/devices/system/cpu/cpu3/topology/thread_siblings_list) != 3,11 ]]; then
    pin=0; say "thread pinning skipped: CPU layout is not 8 cores x 2 with CPU n and n+8 as siblings"
fi

setsid "$app/gravityrush-pc" "$@" &
leader=$!
trap 'kill -TERM -- "-$leader" 2>/dev/null || true' INT TERM

declare -A own=([shadPS4:GpuComm]=0 [gow3:DrawRec]=1 [gow3:VkRecorder]=2 [DrawThread]=3)
rest=4-7,12-15
declare -A applied=()
while kill -0 "$leader" 2>/dev/null; do
    if (( pin )); then
        pid=$(ps -o pid=,comm= -g "$leader" 2>/dev/null | awk '$2 ~ /^gravityrush-r/ {print $1; exit}' || true)
        if [[ -n $pid ]]; then
            for task in /proc/"$pid"/task/*; do
                tid=${task##*/}
                read -r name < "$task/comm" 2>/dev/null || continue
                want=$rest
                [[ -n ${own[$name]+x} ]] && want=${own[$name]}
                [[ ${applied[$tid]:-} == "$want" ]] && continue
                if taskset -p -c "$want" "$tid" >/dev/null 2>&1; then
                    applied[$tid]=$want
                    [[ $want != "$rest" ]] && say "pinned $name ($tid) to CPU $want"
                fi
            done
        fi
    fi
    sleep 2
done
wait "$leader" || rc=$?
say "game exited; deep-sleep block released"
exit "${rc:-0}"
