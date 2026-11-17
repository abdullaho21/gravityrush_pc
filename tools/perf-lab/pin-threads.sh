#!/usr/bin/env bash
# Thread-pinning test: sets CPU affinity per thread of one
# running game process. Only this process's threads change; nothing system-wide. Ryzen 7 7800X3D:
# CPU n and n+8 share core n (lscpu -e).
#   [LAYOUT=1|3|4] tools/perf-lab/pin-threads.sh <runtime-pid>
# Every layout: GPU commands, draw recording, Vulkan recording and the game's DrawThread get cores
# 0-3 alone (CPUs 0-3; siblings 8-11 stay empty).
#   1: everything else on cores 4-7 (CPUs 4-7, 12-15), placed by the scheduler.
#   3: the 8 draw-preparation workers on core 7 only (CPUs 7, 15); everything else on cores 4-6.
#   4: the game's worker pools spread one per CPU (3 x Gfx::DrawModelT on CPUs 4, 5, 6; 3 x
#      Gfx::CullModelT on their siblings 12, 13, 14); everything else on cores 4-7.
# (Layout 2, both pools squeezed onto one core each, collapsed to ~57 FPS: the pools hold 3 threads.)
set -euo pipefail
pid=$1
layout=${LAYOUT:-1}
declare -A own=([shadPS4:GpuComm]=0 [gow3:DrawRec]=1 [gow3:VkRecorder]=2 [DrawThread]=3)
declare -A spread=()          # name -> CPUs handed out one per thread, in thread-id order
rest=4-7,12-15
prep=""                       # CPUs for gow3:DrawPrep* (empty: same as rest)
case $layout in
    1) ;;
    3) rest=4-6,12-14; prep=7,15 ;;
    4) spread=([Gfx::DrawModelT]="4 5 6" [Gfx::CullModelT]="12 13 14") ;;
    *) echo "unknown LAYOUT=$layout" >&2; exit 1 ;;
esac
declare -A next=()
named=0
for tid in $(ls /proc/"$pid"/task | sort -n); do
    name=$(<"/proc/$pid/task/$tid/comm") || continue
    want=$rest
    if [[ -n ${own[$name]+x} ]]; then
        want=${own[$name]}
    elif [[ -n ${spread[$name]+x} ]]; then
        read -r -a cpus <<< "${spread[$name]}"
        i=${next[$name]:-0}
        want=${cpus[i % ${#cpus[@]}]}
        next[$name]=$((i + 1))
    elif [[ -n $prep && $name == gow3:DrawPrep* ]]; then
        want=$prep
    fi
    if taskset -p -c "$want" "$tid" >/dev/null 2>&1 && [[ $want != "$rest" ]]; then
        echo "pinned $name ($tid) -> CPU $want"
        named=$((named + 1))
    fi
done
echo "layout $layout: others -> CPUs $rest; $named threads given their own CPUs"
