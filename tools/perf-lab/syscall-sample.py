#!/usr/bin/env python3
"""Where one game thread is, ~1000 times a second: running, or the kernel function it sleeps in.

usage: syscall-sample.py <pid> <thread name> <seconds> <output .json>

Reads /proc/<pid>/task/<tid>/stat (state, page faults) and .../wchan (where a sleeping thread
waits) — no perf, no ptrace. Writes the counts of (state, wait) pairs, voluntary/involuntary
context switches and minor/major faults over the period.
"""
import json, sys, time
from collections import Counter

pid, name, secs, out = int(sys.argv[1]), sys.argv[2], float(sys.argv[3]), sys.argv[4]
import glob
tid = None
for t in glob.glob(f"/proc/{pid}/task/*"):
    try:
        if open(t + "/comm").read().strip() == name:
            tid = int(t.rsplit("/", 1)[1])
            break
    except OSError:
        pass
if tid is None:
    sys.exit(f"no thread {name}")
base = f"/proc/{pid}/task/{tid}"
NAMES = {0: "read", 1: "write", 7: "poll", 10: "mprotect", 11: "munmap", 9: "mmap", 13: "rt_sigaction",
         14: "rt_sigprocmask", 15: "rt_sigreturn", 16: "ioctl", 24: "sched_yield", 28: "madvise",
         35: "nanosleep", 202: "futex", 228: "clock_gettime", 230: "clock_nanosleep", 232: "epoll_wait",
         281: "epoll_pwait", 186: "gettid", 39: "getpid", 200: "tkill", 234: "tgkill", 271: "ppoll",
         435: "clone3", 425: "io_uring_setup", 426: "io_uring_enter"}
FUTEX = {0: "WAIT", 1: "WAKE", 9: "WAIT_BITSET", 10: "WAKE_BITSET", 128: "WAIT_PRIVATE", 129: "WAKE_PRIVATE",
         137: "WAIT_BITSET_PRIVATE", 138: "WAKE_BITSET_PRIVATE"}


def status():
    v = {}
    for line in open(base + "/status"):
        k, _, rest = line.partition(":")
        if k in ("voluntary_ctxt_switches", "nonvoluntary_ctxt_switches"):
            v[k] = int(rest)
    f = open(base + "/stat").read()
    f = f[f.rindex(")") + 2:].split()
    v["minflt"], v["majflt"] = int(f[7]), int(f[9])
    return v


counts, futex_ops, futex_addrs = Counter(), Counter(), Counter()
start = status()
t0 = time.monotonic()
n = 0
while time.monotonic() - t0 < secs:
    try:
        st = open(base + "/stat").read()
        state = st[st.rindex(")") + 2]
        # /proc/.../syscall needs ptrace rights (Yama scope 1: ancestors only); wchan does not:
        # the kernel function a sleeping thread waits in ("0" while it runs).
        wchan = open(base + "/wchan").read().strip()
    except OSError:
        break
    key = "running" if state == "R" else (wchan or "?")
    counts[(state, key)] += 1
    n += 1
    time.sleep(0.001)
end = status()
elapsed = time.monotonic() - t0
json.dump({"thread": name, "tid": tid, "samples": n, "seconds": round(elapsed, 2),
           "states": {f"{s} {k}": c for (s, k), c in counts.most_common()},
           "futex_ops": dict(futex_ops.most_common()), "futex_addrs": dict(futex_addrs.most_common(8)),
           "per_second": {k: round((end[k] - start[k]) / elapsed, 1) for k in end}},
          open(out, "w"), indent=1)
