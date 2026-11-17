#!/usr/bin/env python3
"""Recorded-play report: compares replays of a recorded run with the recording.

usage: replay-report.py [--phase 30] <log of the recording> <replay log>...

Times count from the pad recorder's or replay's start ("Runtime: pad recording/replay started at
X ms"); "Camera log" lines (GOW3_CAMERA_LOG=250) give the camera position, "Frame stats ... at X ms"
the end of each 5-s window.

1. Route: how far each replay's camera is from the recording's at the same time (does the replay
   follow the route you played, and from when does it drift).
2. Fix on/off by route stretch: the switch state alternates every --phase seconds and replays start
   with the opposite state of the recording or of each other, so the same stretch of the route is
   measured both ways. A window counts only if it lies wholly inside one state. For each pair of
   runs with opposite states, the mean of (off - on) over stretches cancels a constant difference
   between the two launches, because the run that has the fix off swaps every stretch.
"""
import argparse, math, re, statistics as st

ap = argparse.ArgumentParser()
ap.add_argument("--phase", type=float, default=30.0)
ap.add_argument("logs", nargs="+")
a = ap.parse_args()


def parse(path):
    anchor = None; state = ("0", "0"); changed = -1e18; cams = []; wins = []; cur = None
    for line in open(path, errors="replace"):
        m = re.match(r"Runtime: pad (recording|replay) started at ([\d.]+) ms", line)
        if m and anchor is None:
            anchor = float(m.group(2)); continue
        m = re.match(r"Camera log \d+ ([\d.]+) pos (\S+) (\S+) (\S+)", line)
        if m:
            if anchor is not None:
                cams.append(((float(m.group(1)) - anchor) / 1000, tuple(float(x) for x in m.group(2, 3, 4))))
            last_ms = float(m.group(1)); continue
        m = re.match(r"Runtime: disabled optimizations (mask|second word)=(\d+)", line)
        if m:
            state = (m.group(2), state[1]) if m.group(1) == "mask" else (state[0], m.group(2))
            # The change takes effect around the previous timestamp seen; windows whose start is
            # before it (plus a margin) are dropped below.
            changed = wins[-1]["end"] if wins else -1e18
            continue
        m = re.match(r"Frame stats: ([\d.]+) FPS.*?GPU thread ([\d.]+) us/draw, (\d+) draws/frame.*; at ([\d.]+) ms", line)
        if m:
            end = float(m.group(4))
            cur = {"end": end, "fps": float(m.group(1)), "dpf": int(m.group(3)), "state": state,
                   "since_change": end - changed, "hits": 0, "miss": 0, "gen": 0}
            wins.append(cur); continue
        m = re.search(r"texture sets: (\d+) hits, (\d+) misses", line)
        if m and cur is not None:
            cur["hits"] += int(m.group(1)); cur["miss"] += int(m.group(2)); continue
        m = re.search(r"texture set misses: other key (\d+), generation (\d+)", line)
        if m and cur is not None:
            cur["gen"] += int(m.group(2))
    if anchor is None:
        raise SystemExit(f"{path}: no 'pad recording/replay started at' line (built before the recorder timestamps?)")
    out = []
    for w in wins:
        t = (w["end"] - anchor) / 1000
        # Clean window: after the start, at least 6 s after the last switch (a window is about 5 s).
        if t - 6.0 < 0 or w["since_change"] < 6000:
            continue
        k = int(t // a.phase)
        if int((t - 5.5) // a.phase) != k:
            continue
        out.append(dict(w, t=t, k=k))
    return cams, out


def label_of(state):
    return "on" if state == ("0", "0") else "off"


runs = [(p.rsplit("/", 1)[-1].removeprefix("log-").removesuffix(".txt"), *parse(p)) for p in a.logs]

print("1. Route: camera distance from the recording at the same time (world units)")
ref_name, ref_cams, _ = runs[0]
def pos_at(cams, t):
    # Camera sample nearest to t (they come every 0.25 s).
    lo, hi = 0, len(cams) - 1
    if not cams: return None
    while lo < hi:
        mid = (lo + hi) // 2
        if cams[mid][0] < t: lo = mid + 1
        else: hi = mid
    best = min((i for i in (lo - 1, lo) if 0 <= i < len(cams)), key=lambda i: abs(cams[i][0] - t))
    return cams[best][1] if abs(cams[best][0] - t) < 1.0 else None
end_t = ref_cams[-1][0] if ref_cams else 0
for name, cams, _ in runs[1:]:
    marks, first5, first25, d_all = [], None, None, []
    t = 0.0
    while t <= end_t:
        p, q = pos_at(ref_cams, t), pos_at(cams, t)
        if p and q:
            d = math.dist(p, q); d_all.append(d)
            if first5 is None and d > 5: first5 = t
            if first25 is None and d > 25: first25 = t
        t += 1.0
    checkpoints = [10, 30, 60, 120, 240, 480]
    cp = "  ".join(f"{c}s {math.dist(pos_at(ref_cams, c), pos_at(cams, c)):.1f}" for c in checkpoints
                   if c <= end_t and pos_at(ref_cams, c) and pos_at(cams, c))
    print(f"  {name}: {len(d_all)} s compared, median {st.median(d_all) if d_all else float('nan'):.1f}; "
          f"first > 5 at {first5 if first5 is not None else '-'} s, > 25 at {first25 if first25 is not None else '-'} s; {cp}")

print(f"\n2. Fix on/off ({a.phase:.0f}-s stretches, clean windows only)")
for name, _, wins in runs:
    for s in ("on", "off"):
        v = [w for w in wins if label_of(w["state"]) == s]
        if not v: continue
        hits = sum(w["hits"] for w in v); miss = sum(w["miss"] for w in v); gen = sum(w["gen"] for w in v)
        print(f"  {name:18} fix {s:3}: {len(v):3} windows, FPS {st.mean(w['fps'] for w in v):6.1f}, "
              f"draws/frame {st.mean(w['dpf'] for w in v):5.0f}, texture sets {hits / max(1, hits + miss):.1%} hits, "
              f"{gen} generation misses ({gen / len(v):.0f}/window)")

def per_stretch(wins):
    out = {}
    for w in wins:
        out.setdefault(w["k"], []).append(w)
    return {k: (label_of(v[0]["state"]), st.mean(w["fps"] for w in v), st.mean(w["gen"] for w in v))
            for k, v in out.items() if len({label_of(w["state"]) for w in v}) == 1}

print("\n  Paired by stretch (off minus on, same stretch of the route, two launches):")
stretches = [(name, per_stretch(wins)) for name, _, wins in runs]
for i in range(len(stretches)):
    for j in range(i + 1, len(stretches)):
        (n1, s1), (n2, s2) = stretches[i], stretches[j]
        pairs = []
        for k in sorted(set(s1) & set(s2)):
            (st1, f1, g1), (st2, f2, g2) = s1[k], s2[k]
            if st1 == st2: continue
            off, on = ((f1, g1), (f2, g2)) if st1 == "off" else ((f2, g2), (f1, g1))
            pairs.append(((off[0] - on[0]) / on[0] * 100, off[1] - on[1], st1 == "off"))
        if len(pairs) < 2:
            print(f"  {n1} vs {n2}: same states in every stretch, no pairs"); continue
        d = [p[0] for p in pairs]; g = [p[1] for p in pairs]
        ci = 2 * st.stdev(d) / math.sqrt(len(d))
        bal = sum(p[2] for p in pairs)
        print(f"  {n1} vs {n2}: {len(d)} stretches ({bal} with {n1} off): FPS off vs on {st.mean(d):+.1f}% "
              f"(+/- {ci:.1f}), generation misses off minus on {st.mean(g):+.0f}/window")
