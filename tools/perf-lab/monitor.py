#!/usr/bin/env python3
"""Once-a-second system monitor for one game run (run-one.sh MON=1).

usage: monitor.py <game pid> <output .jsonl>

Each line: t (CLOCK_MONOTONIC ms, the clock of the game's "Frame stats ... at X ms"), the game's
threads (name, CPU % of one CPU, the CPU it ran on last, involuntary context switches), every CPU's
busy % and clock, the other processes using the most CPU (and on which CPUs), and the GPU's busy %,
shader clock and power (amdgpu sysfs). Reads /proc and /sys only; stops when the game exits.
"""
import glob, json, os, sys, time

pid = int(sys.argv[1])
out = open(sys.argv[2], "w")
hz = os.sysconf("SC_CLK_TCK")
ncpu = os.cpu_count()


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def stat_fields(text):
    # comm may contain spaces: the fields after the closing parenthesis are positional.
    rest = text[text.rindex(")") + 2:].split()
    return rest  # rest[0] = state (field 3)


def cpu_times():
    t = {}
    for line in (read("/proc/stat") or "").splitlines():
        if line.startswith("cpu") and line[3:4].isdigit():
            p = line.split()
            vals = list(map(int, p[1:]))
            idle = vals[3] + vals[4]
            t[int(p[0][3:])] = (sum(vals), idle)
    return t


def gpu_dir():
    for card in sorted(glob.glob("/sys/class/drm/card[0-9]")):
        dev = card + "/device"
        if read(dev + "/gpu_busy_percent") is not None:
            return dev
    return None


gdev = gpu_dir()
hwmon = glob.glob(gdev + "/hwmon/hwmon*")[0] if gdev and glob.glob(gdev + "/hwmon/hwmon*") else None


def gpu():
    if not gdev:
        return None
    busy = read(gdev + "/gpu_busy_percent")
    sclk = None
    for line in (read(gdev + "/pp_dpm_sclk") or "").splitlines():
        if line.rstrip().endswith("*"):
            sclk = line.split(":")[1].strip().rstrip("*").strip()
    power = None
    if hwmon:
        for name in ("power1_average", "power1_input"):
            v = read(f"{hwmon}/{name}")
            if v:
                power = int(v) / 1e6
                break
    return {"busy": int(busy) if busy else None, "sclk": sclk, "power_w": power}


def threads():
    res = {}
    for task in glob.glob(f"/proc/{pid}/task/*"):
        tid = int(task.rsplit("/", 1)[1])
        s = read(task + "/stat")
        if not s:
            continue
        f = stat_fields(s)
        name = s[s.index("(") + 1:s.rindex(")")]
        ticks = int(f[11]) + int(f[12])  # utime + stime (fields 14, 15)
        sys_ticks = int(f[12])
        minflt = int(f[7])               # minor page faults (field 10)
        cpu = int(f[36])                 # processor (field 39)
        inv = 0
        st = read(task + "/status") or ""
        for line in st.splitlines():
            if line.startswith("nonvoluntary_ctxt_switches"):
                inv = int(line.split()[1])
        res[tid] = (name, ticks, cpu, inv, sys_ticks, minflt)
    return res


def processes():
    res = {}
    for d in glob.glob("/proc/[0-9]*"):
        p = int(d[6:])
        if p == pid:
            continue
        s = read(d + "/stat")
        if not s:
            continue
        f = stat_fields(s)
        name = s[s.index("(") + 1:s.rindex(")")]
        res[p] = (name, int(f[11]) + int(f[12]), int(f[36]))
    return res


prev_t, prev_c, prev_p = threads(), cpu_times(), processes()
prev_time = time.monotonic()
while os.path.exists(f"/proc/{pid}"):
    time.sleep(1.0)
    now = time.monotonic()
    dt = now - prev_time
    cur_t, cur_c, cur_p = threads(), cpu_times(), processes()
    th = []
    for tid, (name, ticks, cpu, inv, sys_ticks, minflt) in cur_t.items():
        if tid in prev_t:
            pct = 100.0 * (ticks - prev_t[tid][1]) / hz / dt
            if pct >= 1.0:
                sys_pct = 100.0 * (sys_ticks - prev_t[tid][4]) / hz / dt
                th.append([name, tid, round(pct, 1), cpu, inv - prev_t[tid][3], round(sys_pct, 1),
                           round((minflt - prev_t[tid][5]) / dt)])
    cpus = {}
    for c, (total, idle) in cur_c.items():
        if c in prev_c:
            dtot = total - prev_c[c][0]
            didle = idle - prev_c[c][1]
            busy = 100.0 * (dtot - didle) / dtot if dtot else 0.0
            freq = read(f"/sys/devices/system/cpu/cpu{c}/cpufreq/scaling_cur_freq")
            cpus[c] = [round(busy, 1), int(freq) // 1000 if freq else None]
    others = []
    for p, (name, ticks, cpu) in cur_p.items():
        if p in prev_p:
            pct = 100.0 * (ticks - prev_p[p][1]) / hz / dt
            if pct >= 2.0:
                others.append([name, p, round(pct, 1), cpu])
    others.sort(key=lambda x: -x[2])
    out.write(json.dumps({"t": round(now * 1000, 1), "threads": sorted(th, key=lambda x: -x[2]),
                          "cpus": cpus, "others": others[:8], "gpu": gpu()}) + "\n")
    out.flush()
    prev_t, prev_c, prev_p, prev_time = cur_t, cur_c, cur_p, now
