#!/usr/bin/env bash
# Runs a command while holding a PM QoS CPU-latency request.
# /dev/cpu_dma_latency (group audio): the request lasts only while the file is open, so it ends with
# this script. QOS_US=20 lets cores use C1/C2 (1 and 18 us exit latency) but not C3 (350 us).
#   tools/perf-lab/with-qos.sh <command...>
set -euo pipefail
us=${QOS_US:-20}
c3() { cat /sys/devices/system/cpu/cpu*/cpuidle/state3/usage | awk '{s+=$1} END {print s}'; }
exec 3>/dev/cpu_dma_latency
python3 -c 'import struct,sys; sys.stdout.buffer.write(struct.pack("i", int(sys.argv[1])))' "$us" >&3
before=$(c3)
"$@" || rc=$?
after=$(c3)
exec 3>&-
echo "QoS ${us} us held; C3 entries across all cores during the run: $((after - before))"
exit "${rc:-0}"
