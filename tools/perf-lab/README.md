# perf-lab: measuring the Linux build

Scripts used to measure FPS changes of this port on Linux (November 2026). They start a build on a
**copy** of your data, drive it with scripted pad input and read the game's own log. None of them
changes your saves or settings.

Layout (all ignored by git except the scripts):

| Path | What |
| --- | --- |
| `builds/current/` | an unpacked release folder (the one with `gravityrush-pc`); `APP=` picks another |
| `data-template/` | a copy of `~/.local/share/gravityrush-pc` with test settings (e.g. `vsync=0`, `fps_limit=0`) |
| `results/` | logs, windows and summaries of each run |
| `recordings/` | recorded play (`selftest.pad` is a scripted 60-s route) |

## Scripts

- `run-one.sh <app> <label> [settle_s] [measure_s]`: one run. Loads SAVEAUTO by tapping Cross, waits for
  gameplay, settles, then records the `Frame stats` windows. Options by environment:
  `PIN=1` (pin-threads.sh), `PAD_HOLD="rx=255"` (hold an input, e.g. turn the camera), `SHOT=1` (one
  screenshot of the game window only), `PERF=1` (perf record), `TOGGLE_AB="w1 w2"` with `PHASE`/`INVERT`
  (switch optimizations off and on within one launch: `GOW3_TOGGLE_FILE`), `INI="key=value ..."`
  (settings for this run), `RECORD=`/`REPLAY=` (pad input by wall clock), `FRAME_RECORD=`/`FRAME_REPLAY=`
  (pad input and the game's clock per frame).
- `toggle-summary.py results/window-<label>.txt`: FPS and texture-set counters by toggle state.
- `with-qos.sh <command>`: holds a 20 µs `/dev/cpu_dma_latency` request while the command runs (deep CPU
  sleep blocked; needs write access to that device).
- `pin-threads.sh <pid>`: one core each for the four busiest threads (8-core CPUs where CPU n and n+8
  share a core).
- `play-fast.sh`: plays with the hold and the pinning (the fastest setup measured on a 7800X3D).
- `train-pgo.sh`: the PGO training run.
- `monitor.py` (run-one.sh `MON=1`): once a second, the game's threads (CPU %, kernel %, page faults, last
  CPU), every CPU's load and clock, the busiest other programs and the GPU; `mon-report.py results/<label>
  ...` joins it with the Frame stats windows and ranks what moves with the FPS.
- `syscall-sample.py` (run-one.sh `SAMPLETHREADS="DrawThread ..."`): ~1000 times a second, whether those
  threads run or where in the kernel they wait (`wchan`), plus context switches and page faults.
- `record-play.sh [name]` / `replay.sh [name] [runs]`: record your own run, then replay it automatically;
  `replay-report.py` and `frame-route.py` compare the routes and the toggle states.

## What the measurements showed (7800X3D, RX 9070 XT, Mesa 26.2)

- Between launches the FPS of the same build varied by about ±12 % (261–299 FPS). Cause: glibc's heap
  trim threshold (128 KiB, frozen by the port's own `mallopt(M_MMAP_THRESHOLD)`) made the game's
  DrawThread fault ~850 fresh pages per frame in most launches; fixed in 0.1.15-4 (273–288 FPS). The
  rest follows other programs' CPU use (a busy browser tab, also on the pinned cores' SMT twins).
  Still compare changes **within one launch** (`TOGGLE_AB`) where you can.
- Blocking deep CPU sleep (C3) during play: +10 % with a PGO build (without the block PGO was 3.5 %
  slower).
- The draw-recording ports (bulk descriptors, sampler memo, texture-set stamps) each change FPS by
  about 1 % or less here; texture-set stamps cut texture-set "generation" misses by 85–96 % while
  moving through the city.
- Replays drift from the recorded route: wall-clock replays after ~10 s of real play, frame-exact
  replays (`GOW3_FRAME_REPLAY`) after 5–35 s. The game's clock and `time()` are replayed; the rest
  (likely the game's own thread timing) is not. Use replays for "similar play", not for the same frames.
