# Gravity Rush Remastered PC port: Linux build (unofficial)

This fork adds a few small changes to [Luca Pazienza's Gravity Rush PC port](https://github.com/LucaPazienza/gravityrush_pc)
so it builds and runs natively on Linux. The port itself, and nearly all of the work, is Luca's.
Thank you, Luca.

Linux is not supported upstream, so please report Linux problems here, not to Luca.

- Made for **Arch Linux**. I play it on CachyOS with an AMD graphics card, and it is playable on my
  end. Other distributions, the Steam Deck and the Steam Machine are not tested.
- You need your own copy of the game, unpacked (the folder with `eboot.bin`, `sce_module` and
  `sce_sys`). No game files are included. Tested with the EU release CUSA01113, version 01.00.
- I plan to follow Luca's releases about once a week, sometimes sooner.

## Install

From the [Releases](https://github.com/abdullaho21/gravityrush_pc/releases) page, either:

- the Arch package: `sudo pacman -U gravityrush-pc-bin-<version>-x86_64.pkg.tar.zst`, then run
  `gravityrush-pc /path/to/your/game`; or
- the tarball: extract it anywhere, then run `./gravityrush-pc /path/to/your/game` inside it
  (the libraries come from your system: `sudo pacman -S --needed python sdl3 ffmpeg vulkan-icd-loader freetype2 fmt zydis xxhash libx11`).

The game folder is remembered, so later just run `gravityrush-pc` (or use the menu entry the
package installs). Settings, saves and logs are in `~/.local/share/gravityrush-pc`. In game,
Insert (or R3+L2) opens the port's menu.

FSR 4.1.1 needs files made from AMD's own upscaler DLL, so they are not included (Luca's port does not
ship them either). If a game you own comes with AMD's FSR 4.1.x DLLs, build them with
`tools/fsr4cap/build_assets.sh` from the source tree, put the `fsr4_411` folder in
`~/.local/share/gravityrush-pc/` and set `upscaler=fsr411` in `gravityrush.ini` there.

## Changes from Luca's version

- Fibers (`libSceFiber`) on `ucontext`, plus small Linux build fixes.
- `run.py` starts the Linux runtime, and the in-game "Apply and restart" works.
- One small speed fix: no copy of the fetch shader data on every draw (toggle bit 61 turns it off).

## Build from source

```bash
sudo pacman -S --needed base-devel git cmake ninja pkgconf python glslang vulkan-headers vulkan-icd-loader \
    sdl3 ffmpeg freetype2 fmt boost robin-map zydis xxhash libx11
git clone --recursive -b linux https://github.com/abdullaho21/gravityrush_pc && cd gravityrush_pc
git clone --depth 1 -b v3.3.0 https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator vma
CMAKE_INCLUDE_PATH="$PWD/vma/include" CPLUS_INCLUDE_PATH="$PWD/gpu/third_party/xbyak" GOW3_RELEASE=1 bash build.sh
linux/gravityrush-pc /path/to/your/game
```
