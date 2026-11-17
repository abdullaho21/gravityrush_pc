#!/usr/bin/env python3
"""What moves with the FPS: joins each Frame stats window of a run with its monitor samples.

usage: mon-report.py results/<label> [results/<label> ...]
  reads results/window-<label>.txt (Frame stats with "at X ms") and results/mon-<label>.jsonl
  (monitor.py). Prints per run its windows, then over all windows the correlation of FPS with
  each measured quantity (Pearson r; |r| near 1 = moves with the FPS).
"""
import json, math, re, statistics as st, sys
from collections import defaultdict

KEY = {"gravityrush-run": "main", "DrawThread": "draw", "Gfx::DrawModelT": "model",
       "Gfx::CullModelT": "cull", "Gfx::DrawMgrThr": "drawmgr", "shadPS4:GpuComm": "gpucomm",
       "gow3:DrawRec": "drawrec", "gow3:VkRecorder": "vkrec", "BackgroundFiber": "fiber"}
GAME_CORES_REST = set(range(4, 8)) | set(range(12, 16))
NCPU = 16


def sibling(c):
    return (c + 8) % 16


def load(base):
    windows = []
    for line in open(base.replace("results/", "results/window-") + ".txt", errors="replace"):
        m = re.match(r"Frame stats: ([\d.]+) FPS.*?GPU thread ([\d.]+) us/draw, (\d+) draws/frame, "
                     r"idle ([\d.]+)%.*; at ([\d.]+) ms", line)
        if m:
            windows.append({"fps": float(m.group(1)), "us": float(m.group(2)), "dpf": int(m.group(3)),
                            "idle": float(m.group(4)), "end": float(m.group(5))})
    samples = [json.loads(l) for l in open(base.replace("results/", "results/mon-") + ".jsonl")]
    return windows, samples


def window_metrics(w, samples):
    s = [x for x in samples if w["end"] - 5000 < x["t"] <= w["end"]]
    if not s:
        return None
    m = defaultdict(list)
    for x in s:
        per = defaultdict(float); cpu_of = {}; inv = defaultdict(int)
        for name, tid, pct, cpu, invol, *_ in x["threads"]:
            k = KEY.get(name, "prep" if name.startswith("gow3:DrawPrep") else "other_game")
            per[k] += pct; inv[k] += invol
            if k in ("main", "draw"):
                cpu_of[k] = cpu
        for k in ("main", "draw", "model", "cull", "drawmgr", "gpucomm", "drawrec", "vkrec", "prep",
                  "fiber", "other_game"):
            m[k + "%"].append(per[k])
        for k in ("main", "draw"):
            m[k + "_invol"].append(inv[k])
            if k in cpu_of:
                c = cpu_of[k]
                m[k + "_sibling_busy%"].append(x["cpus"][str(sibling(c))][0])
                if x["cpus"][str(c)][1]:
                    m[k + "_mhz"].append(x["cpus"][str(c)][1])
                m[k + "_on_rest"].append(1.0 if c in GAME_CORES_REST else 0.0)
        others_rest = sum(p for _, _, p, c in x["others"] if c in GAME_CORES_REST)
        others_all = sum(p for _, _, p, c in x["others"])
        m["others_all%"].append(others_all)
        m["others_on_rest%"].append(others_rest)
        rest_busy = [x["cpus"][str(c)][0] for c in GAME_CORES_REST]
        m["rest_cpus_busy%"].append(st.mean(rest_busy))
        mhz = [v[1] for v in x["cpus"].values() if v[1]]
        if mhz:
            m["all_mhz"].append(st.mean(mhz))
        if x.get("gpu"):
            g = x["gpu"]
            if g.get("busy") is not None:
                m["gpu_busy%"].append(g["busy"])
            if g.get("sclk"):
                m["gpu_sclk"].append(float(re.sub(r"[^\d.]", "", g["sclk"])))
            if g.get("power_w"):
                m["gpu_w"].append(g["power_w"])
        m["top_other"].append(x["others"][0][0] if x["others"] else "")
    out = {k: st.mean(v) for k, v in m.items() if v and not isinstance(v[0], str)}
    tops = [t for t in m["top_other"] if t]
    out["top_other"] = max(set(tops), key=tops.count) if tops else ""
    return out


def pearson(a, b):
    if len(a) < 3:
        return float("nan")
    ma, mb = st.mean(a), st.mean(b)
    va = math.sqrt(sum((x - ma) ** 2 for x in a)); vb = math.sqrt(sum((y - mb) ** 2 for y in b))
    return sum((x - ma) * (y - mb) for x, y in zip(a, b)) / (va * vb) if va and vb else float("nan")


allrows = []
for base in sys.argv[1:]:
    windows, samples = load(base)
    rows = []
    for w in windows:
        mm = window_metrics(w, samples)
        if mm:
            rows.append({**w, **mm, "run": base.rsplit("/", 1)[-1]})
    allrows += rows
    if not rows:
        continue
    print(f"== {base.rsplit('/', 1)[-1]}: FPS {st.mean(r['fps'] for r in rows):.1f}, GPU-thread idle "
          f"{st.mean(r['idle'] for r in rows):.1f}%")
    for r in rows:
        print(f"  {r['fps']:6.1f} fps idle {r['idle']:4.1f}% | main {r.get('main%', 0):5.1f}% sib {r.get('main_sibling_busy%', 0):5.1f}% "
              f"{r.get('main_mhz', 0):4.0f}MHz | draw {r.get('draw%', 0):5.1f}% sib {r.get('draw_sibling_busy%', 0):5.1f}% | "
              f"model {r.get('model%', 0):5.1f} cull {r.get('cull%', 0):5.1f} fiber {r.get('fiber%', 0):5.1f} | "
              f"others {r.get('others_all%', 0):5.1f}% (on game cores {r.get('others_on_rest%', 0):4.1f}) top {r['top_other'][:14]:14} | "
              f"gpu {r.get('gpu_busy%', 0):3.0f}% {r.get('gpu_sclk', 0):4.0f}MHz")

if len(allrows) >= 4:
    print("\nCorrelation with FPS over all windows (n=%d):" % len(allrows))
    keys = sorted({k for r in allrows for k, v in r.items() if isinstance(v, (int, float)) and k not in ("end", "fps")})
    res = []
    for k in keys:
        pairs = [(r["fps"], r[k]) for r in allrows if k in r]
        if len(pairs) >= 4:
            res.append((pearson([p[0] for p in pairs], [p[1] for p in pairs]), k, len(pairs)))
    for r, k, n in sorted(res, key=lambda x: -abs(x[0]) if not math.isnan(x[0]) else 0):
        print(f"  {k:22} r={r:+.2f} (n={n})")
