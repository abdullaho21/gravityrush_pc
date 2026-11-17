#!/usr/bin/env python3
"""Frame-exact route check: compares the camera of frame-exact runs frame by frame.

usage: frame-route.py <reference log> <other log>...

"Camera log ... frame N" lines (GOW3_CAMERA_LOG with a frame recording or replay running) give the
camera position of game frame N. The camera is sampled every 250 ms of wall time, so two runs rarely
sample the same frame: each sample of a run is compared with the reference sample of the nearest frame
(at most 2 frames apart). Seconds are game time, taken from the reference run (recorded in real time).
"""
import bisect, math, re, statistics as st, sys


def load(path):
    out = []  # (frame, wall ms, pos)
    for line in open(path, errors="replace"):
        m = re.match(r"Camera log \d+ ([\d.]+) pos (\S+) (\S+) (\S+) .* frame (-?\d+)", line)
        if m and int(m.group(5)) >= 0:
            out.append((int(m.group(5)), float(m.group(1)), tuple(float(x) for x in m.group(2, 3, 4))))
    out.sort()
    return out


ref = load(sys.argv[1])
if not ref:
    raise SystemExit(f"{sys.argv[1]}: no camera lines with a frame index")
ref_frames = [r[0] for r in ref]
t0 = ref[0][1] - 0.0


def ref_at(frame):
    i = bisect.bisect_left(ref_frames, frame)
    best = min((j for j in (i - 1, i) if 0 <= j < len(ref)), key=lambda j: abs(ref[j][0] - frame))
    return ref[best] if abs(ref[best][0] - frame) <= 2 else None


def secs(frame):
    r = ref_at(frame) or ref[min(bisect.bisect_left(ref_frames, frame), len(ref) - 1)]
    return (r[1] - ref[0][1]) / 1000 + ref[0][0] / 240


print(f"reference {sys.argv[1].rsplit('/', 1)[-1]}: frames {ref[0][0]}..{ref[-1][0]}, {len(ref)} camera samples")
for path in sys.argv[2:]:
    run = load(path)
    d = []
    for frame, _, pos in run:
        r = ref_at(frame)
        if r:
            d.append((frame, math.dist(pos, r[2])))
    name = path.rsplit("/", 1)[-1]
    if not d:
        print(f"  {name}: no matching frames"); continue
    first = {lim: next((f for f, x in d if x > lim), None) for lim in (0.01, 0.5, 5.0)}
    marks = "  ".join(f"> {lim}: frame {f} (~{secs(f):.0f} s)" if f is not None else f"> {lim}: never"
                      for lim, f in first.items())
    print(f"  {name}: {len(d)} matched samples up to frame {d[-1][0]} (~{secs(d[-1][0]):.0f} s); "
          f"distance median {st.median(x for _, x in d):.3f}, max {max(x for _, x in d):.2f}; {marks}")
