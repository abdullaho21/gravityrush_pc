<p align="center">
  <img src="launcher/gravityrush.png" alt="Gravity Rush PC port icon" width="160">
</p>

# Gravity Rush Remastered — Linux build

An unofficial Linux build of [Luca Pazienza's Gravity Rush Remastered PC port](https://github.com/LucaPazienza/gravityrush_pc),
made possible by his work. The port itself, and nearly all of the work, is Luca's; this fork only adds the
small changes needed to run it natively on Linux. Thank you, Luca. His original README is in
[README-LUCA.md](README-LUCA.md).

Linux is not supported upstream, so please report Linux problems
[here](https://github.com/abdullaho21/gravityrush_pc/issues), not to Luca.

**[Download the latest release](https://github.com/abdullaho21/gravityrush_pc/releases/latest)**

- For 64-bit Linux with glibc 2.39 or newer: Ubuntu 24.04, Debian 13, Fedora 40, SteamOS 3.7, Arch
  and later ones. I play it on CachyOS with an AMD graphics card, and it is playable on my end.
  Other distributions, the Steam Deck and the Steam Machine are not tested by me (see Steam Deck below).
- You need your own copy of the game, unpacked (the folder with `eboot.bin`, `sce_module` and
  `sce_sys`). No game files are included. Tested with the EU release CUSA01113, version 01.00.
- I plan to follow Luca's releases about once a week, sometimes sooner.

## Install

From the [Releases](https://github.com/abdullaho21/gravityrush_pc/releases) page, either:

- the Arch package: `sudo pacman -U gravityrush-pc-bin-<version>-x86_64.pkg.tar.zst`, then run
  `gravityrush-pc /path/to/your/game`; or
- the tarball: extract it anywhere, then run `./gravityrush-pc /path/to/your/game` inside it
  (SDL3, FFmpeg and the other libraries it needs are inside; from your system it uses Python 3, a
  Vulkan 1.3 driver, libX11 and FreeType, which desktop systems have).

The game folder is remembered, so later just run `gravityrush-pc` (or use the menu entry the
package installs). Settings, saves and logs are in `~/.local/share/gravityrush-pc`. In game,
Insert (or R3+L2) opens the port's menu.

FSR 4.1.1 needs files made from AMD's own upscaler DLL, so they are not included (Luca's port does not
ship them either). If a game you own comes with AMD's FSR 4.1.x DLLs, build them with
`tools/fsr4cap/build_assets.sh` from the source tree, put the `fsr4_411` folder in
`~/.local/share/gravityrush-pc/` and set `upscaler=fsr411` in `gravityrush.ini` there.

## Frame generation

AMD FSR 3.1 frame generation (2x) is built in: a generated frame is shown between two real ones, so
about twice the frames reach the screen while the game itself runs as before. Switch it on in the
launcher (Video) or in game (Insert or R3+L2 > Performance > Frame generation); it applies at once.

- It needs a temporal pass: FSR 3.1, FSR 4, DLSS or TAA (Image tab). Without one the overlay says
  "inactive". The HUD is never interpolated: it is copied from the real frame.
- Best with a frame rate limit (for example 60 → 120 shown on a 120 Hz screen) or VSync off. With
  VSync on and a 60 Hz screen the game drops to 30 to show 60.
- Cost here: about 1 ms per real frame at 1440p (RX 9070 XT). It adds about half a frame of input delay.
- AMD's newer FSR 4 frame generation (the machine-learning one) exists only as AMD's signed DirectX 12
  component and needs an RDNA 4 card, so it cannot run in this Vulkan port or on the Steam Deck. FSR 4
  upscaling and FSR 3.1 frame generation work together.

## Steam Deck

The release is tested in a clean Arch Linux container (SteamOS is built on Arch) besides Ubuntu and
Debian, and needs nothing beyond what SteamOS 3.7 or newer has. I have not played it on a Deck myself.
A starting point there: render resolution 720p, FSR 3.1 or TAA, a 30 or 45 FPS limit and frame
generation on (60 or 90 shown). FSR 4 needs an RDNA 4 card; on the Deck the port uses FSR 3.1 instead.

## Changes from Luca's version

### Start and now

Build 2 (0.1.15-2, Luca's port with only the Linux changes) against build 4 (0.1.15-4). Measured on one PC
(Ryzen 7 7800X3D, Radeon RX 9070 XT, Mesa 26.2), standing in the view of the first save, render
resolution 1440p, FSR 4.1.1, VSync off, no frame limit, draw pipe on (`GOW3_DRAW_PIPE=1`; off by
default). Each launch is the average of 60 seconds. The build 2 numbers come from its exact source built
the same way; the page faults before the fix were counted in build 3, which has the same memory code.

| | Build 2 (start) | Build 4 (now) |
| --- | --- | --- |
| FPS, deep CPU sleep blocked + busiest threads pinned (`tools/perf-lab/play-fast.sh`) | 256 (1 launch) | **273–289** (4 launches, average 283) |
| FPS, plain start | 250–251 (2 launches) | not measured |
| Spread between launches of one build | 261–306 (build 3, 7 launches) | 273–289 |
| Page faults per frame on the game's draw thread | up to ~850 (build 3) | **0** |
| Frame generation | – | **FSR 3.1 2x**: 60 → 120 FPS shown, even 8.3 ms frames |
| Overlay | Luca's (FPS, frame time, GPU, CPU, memory) | + frame-time graph, frame generation status |
| Draw recording | – | bulk descriptor writes, sampler memo, texture-set stamps (~1 % or less each) |
| Release start check | Ubuntu 24.04, Debian 13 | + Arch Linux (the base of SteamOS) |
| Measuring tools | – | `tools/perf-lab`: same-launch A/B switches, system monitor, recorded play |

Faster on this PC, but not part of the release because they depend on the machine: a PGO build
trained on my play, blocking deep CPU sleep (costs power, bad for a Steam Deck's battery) and pinning
threads to cores (written for 8-core CPUs). Together they reached 303 FPS in one launch here
(`tools/perf-lab`).

### What carries over to other PCs

- **Built for any 64-bit PC:** no CPU-specific instructions (`-march`), built against glibc 2.39 in a
  container and started on clean Ubuntu 24.04, Debian 13 and Arch Linux before every release (that check
  loads every library and runs a Vulkan test on a software driver; it does not play the game).
- **Heap fix:** applies wherever glibc is the C library (every desktop Linux and SteamOS). The page faults
  came from the port's own memory use, not from this PC, so other CPUs should lose the same frame time;
  how much FPS that is depends on the frame rate. Measured only here, with the draw pipe on.
- **Frame generation:** needs two common Vulkan features (storage images without a format, push
  descriptors), which AMD's Mesa driver has on older chips too; checked when it starts, and it switches
  itself off with a message where they are missing. Its cost on weaker graphics chips is not measured.
  Off by default.
- **Draw-recording changes:** plain CPU code, no hardware assumptions; each can be switched off live.
- **Not tested on another PC, an NVIDIA or Intel graphics card, a Steam Deck or a Steam Machine.**
  Reports are welcome.

### All changes

- Fibers (`libSceFiber`) on `ucontext`, plus small Linux build fixes.
- `run.py` starts the Linux runtime, and the in-game "Apply and restart" works.
- One small speed fix: no copy of the fetch shader data on every draw (toggle bit 61 turns it off).
- Steadier and faster frame rate: the port kept one heap for all threads but left glibc's trim
  threshold at 128 KiB, so in most launches a large per-frame buffer was handed back to the kernel and
  faulted in again every frame (~850 page faults, ~0.4 ms per frame on the game's DrawThread). The same
  build ran at 261–299 FPS depending on the launch; with the fix 273–288, all in the fast mode (measured
  in one test view on a 7800X3D; what is left follows other programs' CPU use).
- Frame generation (above), ported from [SpartanPort](https://github.com/FelipePrado0/SpartanPort)
  (#1123) and adapted to Gravity Rush: its GPU thread runs a frame ahead of the flips, so each display
  buffer keeps its own captured frame, and frame generation also works without upscaling.
- Draw recording: bulk descriptor writes, a sampler memo and texture-set region stamps, ported from
  [BevelTipDrip's MediEvil port](https://github.com/BevelTipDrip/medievil_2019_pc_port). Each can be
  switched off live with the second word of `GOW3_TOGGLE_FILE` (bits 1, 2, 4, 8).
- Overlay: a frame-time graph (Insert > Overlay > Frametime graph).
- Testing aids for automated runs: the pad recorder can be started by the `record` token of
  `GOW3_PAD_FILE` (red REC mark, controller held neutral until then), frame-exact recording and replay
  (`GOW3_FRAME_RECORD` / `GOW3_FRAME_REPLAY`), `GOW3_TIME_TRACE` (which threads read which clocks) and
  [tools/perf-lab](tools/perf-lab/README.md) with the measurement scripts.

## Build from source

```bash
sudo pacman -S --needed base-devel git cmake ninja pkgconf python glslang vulkan-headers vulkan-icd-loader \
    sdl3 ffmpeg freetype2 fmt boost robin-map zydis xxhash libx11
git clone --recursive -b linux https://github.com/abdullaho21/gravityrush_pc && cd gravityrush_pc
git clone --depth 1 -b v3.3.0 https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator vma
CMAKE_INCLUDE_PATH="$PWD/vma/include" CPLUS_INCLUDE_PATH="$PWD/gpu/third_party/xbyak" GOW3_RELEASE=1 bash build.sh
linux/gravityrush-pc /path/to/your/game
```

A build made this way uses your system's libraries and only runs on a system like yours. The
release packages are built in a container instead, so they also start on older systems:
`packaging/linux/build-release.sh <version>` (needs podman or docker). It keeps the tarball only
if it starts in clean Ubuntu 24.04, Debian 13 and Arch Linux containers; a release is never built any
other way.

## Credits and license

Luca Pazienza's port, and everyone credited in [README-LUCA.md](README-LUCA.md). Frame generation is
based on FelipePrado0's SpartanPort and FireBurn's FSR-Vulkan; the draw-recording changes on BevelTipDrip's
MediEvil port. GNU GPL v2 or later
([LICENSE](LICENSE)), as Luca's port; third-party components keep their own licenses.

This is an unofficial project, not affiliated with or endorsed by Sony Interactive Entertainment or
Japan Studio. Gravity Rush and all related names belong to their respective owners.
