#!/usr/bin/env python3
"""Same-launch A/B summary: splits a run's Frame stats windows by the
toggle state the runtime last reported ("Runtime: disabled optimizations mask=... / second
word=..."). The first window after each change is dropped (it straddles the change).
usage: toggle-summary.py results/window-<label>.txt"""
import re, statistics as st, sys
state = ("0", "0"); fresh = True; rows = {}; tex = {}; counting = False
for line in open(sys.argv[1], errors="replace"):
    m = re.search(r"texture sets: (\d+) hits, (\d+) misses", line)
    if m and counting:
        t = tex.setdefault(state, [0, 0, 0]); t[0] += int(m.group(1)); t[1] += int(m.group(2)); continue
    m = re.search(r"texture set misses: other key (\d+), generation (\d+)", line)
    if m and counting:
        tex.setdefault(state, [0, 0, 0])[2] += int(m.group(2)); continue
    m = re.match(r"Runtime: disabled optimizations mask=(\d+)", line)
    if m: state = (m.group(1), state[1]); fresh = True; continue
    m = re.match(r"Runtime: disabled optimizations second word=(\d+)", line)
    if m: state = (state[0], m.group(1)); fresh = True; continue
    m = re.match(r"Frame stats: ([\d.]+) FPS.*?GPU thread ([\d.]+) us/draw, (\d+) draws/frame", line)
    if not m: continue
    if fresh: fresh = False; counting = False; continue
    counting = True
    fps, us, dpf = float(m.group(1)), float(m.group(2)), int(m.group(3))
    rows.setdefault(state, []).append((fps, us, dpf))
base = None
for key in sorted(rows, key=lambda k: (k != ("0", "0"), k)):
    v = rows[key]; tput = [f * d / 1000 for f, _, d in v]
    mean = st.mean(tput)
    if base is None: base = mean
    names = {("0", "0"): "all on / layout 1", ("4611686018427387904", "0"): "layout 3 (bit-62 marker)",
             ("9223372036854775808", "0"): "layout 4 (bit-63 marker)"}
    label = names.get(key, f"off mask={key[0]} word2={key[1]}")
    print(f"{label:28} windows {len(v):2}  FPS {st.mean(f for f,_,_ in v):6.1f}  draws/frame {st.mean(d for *_,d in v):6.0f}  "
          f"draws/s {mean:6.0f}k ({(mean/base-1)*100:+.1f}% vs all on)  GPU thread {st.mean(u for _,u,_ in v):.3f} us/draw"
          + (f"  texture sets {tex[key][0]/max(1,tex[key][0]+tex[key][1]):.1%} hits, {tex[key][2]} generation misses" if key in tex else ""))
