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

- Fibers (`libSceFiber`) on `ucontext`, plus small Linux build fixes.
- `run.py` starts the Linux runtime, and the in-game "Apply and restart" works.
- One small speed fix: no copy of the fetch shader data on every draw (toggle bit 61 turns it off).
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
