#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds dist/gravityrush-pc-<version>-x86_64.tar.gz (and its .sha256) from a finished release
# build. packaging/linux/build-release.sh <version> does both steps in the build container; that
# is how releases are made.
# The package has to start on systems other than the build machine (issue #1): the libraries the
# build links against are copied into it, except glibc and the few every system has (Vulkan
# loader, libX11, FreeType, zlib), and packaging/linux/portable.py refuses a build that needs a
# newer glibc than the supported one.
set -euo pipefail
cd "$(dirname "$0")/../.."
version=${1:?usage: packaging/linux/package.sh VERSION}
name="gravityrush-pc-$version-x86_64"
stage="dist/$name"

[[ -x out/gravityrush-runtime && -f out/gpu/libgow3gpu.so ]] || {
    echo 'Build first: GOW3_RELEASE=1 bash build.sh' >&2; exit 1; }
if readelf -d out/gravityrush-runtime | grep -q "RUNPATH.*$PWD"; then
    echo 'out/gravityrush-runtime names the build folder: rebuild with GOW3_RELEASE=1' >&2; exit 1
fi
command -v patchelf >/dev/null || {
    echo 'Need patchelf (the build container has it: packaging/linux/build-release.sh).' >&2; exit 1; }

rm -rf "$stage"
mkdir -p "$stage/out/gpu" "$stage/launcher"
# Debug information is left out (it is most of the size); symbols stay for crash reports.
objcopy --strip-debug out/gravityrush-runtime "$stage/out/gravityrush-runtime"
objcopy --strip-debug out/gpu/libgow3gpu.so "$stage/out/gpu/libgow3gpu.so"
# The shared libraries the two binaries need go next to libgow3gpu.so (SDL3, FFmpeg, xxHash).
python3 packaging/linux/portable.py bundle "$stage"
cp -r scripts patches "$stage/"
# No package unpacker in releases (as in the Windows package): players prepare the game folder.
rm -f "$stage/scripts/pkg_extract.py" "$stage/scripts/pkg_keys.py"
cp run.py LICENSE README.md README-LUCA.md linux/gravityrush-pc linux/gravityrush-pc.desktop "$stage/"
cp launcher/gravityrush.png launcher/gravityrush.bmp "$stage/launcher/"

# Licenses of the code compiled into the two binaries.
licenses="$stage/THIRD-PARTY-LICENSES"
mkdir -p "$licenses"
cp gpu/shadps4/LICENSE "$licenses/shadPS4-LICENSE"
for dir in gpu/third_party/* third_party/*; do
    for file in "$dir"/LICENSE* "$dir"/COPYING* "$dir"/COPYRIGHT*; do
        [[ -f $file ]] && cp "$file" "$licenses/$(basename "$dir")-$(basename "$file")"
    done
done
# The libraries built in the container (packaging/linux/Containerfile): licenses and exact versions.
bundled=${GOW3_BUNDLED_LICENSES:-}
[[ -n $bundled && -f $bundled/VERSIONS ]] || {
    echo 'GOW3_BUNDLED_LICENSES is not set: build with packaging/linux/build-release.sh' >&2; exit 1; }
cp "$bundled"/* "$licenses/"
{
    echo "Third-party code in this package."
    echo
    echo "Compiled into out/gravityrush-runtime and out/gpu/libgow3gpu.so: the shadPS4 video core"
    echo "(GPL-2.0-or-later), the libraries in gpu/third_party and third_party of the source tree,"
    echo "fmt, Zydis, Zycore, robin-map, Boost and Vulkan headers, and GCC's libstdc++ (GPL-3.0-or-later"
    echo "with the GCC Runtime Library Exception). Vulkan Memory Allocator (MIT) is header-only; its"
    echo "license is at the top of vk_mem_alloc.h."
    echo
    echo "Shared libraries in out/gpu, built unmodified from their sources: SDL3 (zlib license),"
    echo "FFmpeg (LGPL-2.1-or-later: built without its GPL and nonfree parts) and xxHash (BSD-2-Clause)."
    echo "You may replace them with your own builds of the same versions."
    echo
    echo "VERSIONS lists the exact sources and FFmpeg's configuration; packaging/linux/Containerfile in"
    echo "the source tree (https://github.com/abdullaho21/gravityrush_pc) builds all of them."
    echo
    echo "Not included, taken from your system: glibc, the Vulkan loader, libX11, FreeType and zlib."
} > "$licenses/README.txt"

find "$stage" -name __pycache__ -prune -exec rm -r {} +
# No game files and nothing a player made (saves, caches, settings, logs) may ship.
forbidden=$(find "$stage" \( -iname eboot.bin -o -iname eboot.elf -o -iname 'boot*.bin' -o -iname sce_module \
    -o -iname sce_sys -o -iname savedata -o -iname user -o -iname cache -o -iname '*.log' \
    -o -iname gravityrush.ini -o -iname fsr4_shaders -o -iname fsr4_411 -o -iname '*.psarc' -o -iname '*.pkg' \
    -o -iname '*.prx' -o -iname '*.sprx' -o -iname pkg_keys.py -o -iname pkg_extract.py \) -print)
if [[ -n $forbidden ]]; then
    echo "Package holds files that must not ship:" >&2
    echo "$forbidden" >&2
    exit 1
fi
# Nothing may name the machine it was built on.
if grep -rlI --null "$HOME" "$stage" >/dev/null 2>&1 || grep -qa "$HOME" "$stage/out/gravityrush-runtime" "$stage/out/gpu/libgow3gpu.so"; then
    echo "Package contains $HOME (build paths): rebuild with -ffile-prefix-map" >&2
    exit 1
fi

# Would it start on another system? (bundled libraries found, glibc old enough)
python3 packaging/linux/portable.py check "$stage"

tar -C dist --owner=0 --group=0 --sort=name -czf "dist/$name.tar.gz" "$name"
(cd dist && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
du -sh "$stage" "dist/$name.tar.gz"
