#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds dist/gravityrush-pc-<version>-x86_64.tar.gz (and its .sha256) from a finished release
# build:  GOW3_RELEASE=1 bash build.sh  then  packaging/linux/package.sh <version>
# The libraries the build links against (SDL3, FFmpeg, Vulkan loader, ...) are not bundled: the
# package is meant for an up-to-date Arch Linux, where they come from the distribution
# (packaging/arch/PKGBUILD lists them).
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

rm -rf "$stage"
mkdir -p "$stage/out/gpu" "$stage/launcher"
# Debug information is left out (it is most of the size); symbols stay for crash reports.
objcopy --strip-debug out/gravityrush-runtime "$stage/out/gravityrush-runtime"
objcopy --strip-debug out/gpu/libgow3gpu.so "$stage/out/gpu/libgow3gpu.so"
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
{
    echo "Third-party code compiled into out/gravityrush-runtime and out/gpu/libgow3gpu.so:"
    echo "the shadPS4 video core (GPL-2.0-or-later) and the libraries in gpu/third_party and"
    echo "third_party of the source tree (one license file each here). Vulkan Memory Allocator"
    echo "(MIT) is header-only; its license is at the top of vk_mem_alloc.h."
    echo "SDL3, FFmpeg, FreeType, fmt, Zydis, xxHash and the Vulkan loader are not included: they are"
    echo "the system's own libraries."
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

tar -C dist --owner=0 --group=0 --sort=name -czf "dist/$name.tar.gz" "$name"
(cd dist && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
du -sh "$stage" "dist/$name.tar.gz"
