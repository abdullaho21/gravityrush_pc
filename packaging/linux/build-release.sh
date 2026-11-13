#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds the Linux release: dist/gravityrush-pc-<version>-x86_64.tar.gz and its .sha256.
#   packaging/linux/build-release.sh <version>      (e.g. 0.1.15-2)
# The build runs in a container (podman or docker; packaging/linux/Containerfile), not on this
# machine: a binary built here would need this machine's library versions and would not start
# on an older system such as SteamOS (issue #1). The container's build folder is out/release,
# so the source tree's own out/ (bash build.sh) is left alone.
# GOW3_PGO=use builds with a profile in pgo/ (it must come from the container's GCC 14).
set -euo pipefail
cd "$(dirname "$0")/../.."
version=${1:?usage: packaging/linux/build-release.sh VERSION}
engine=${CONTAINER_ENGINE:-$(command -v podman || command -v docker || true)}
[[ -n $engine ]] || { echo 'Need podman or docker.' >&2; exit 1; }
image=${GOW3_BUILD_IMAGE:-gravityrush-pc-build}

if [[ ! -f gpu/third_party/fsr-vulkan/CMakeLists.txt || ! -f gpu/third_party/imgui/imgui.h ||
      ! -f gpu/third_party/xbyak/xbyak/xbyak.h ]]; then
    git submodule update --init --recursive
fi
"$engine" build -t "$image" -f packaging/linux/Containerfile packaging/linux
mkdir -p out/release dist
# docker runs as root: use this user, so the files it writes here are not root's.
user=()
[[ $(basename "$engine") != docker ]] || user=(--user "$(id -u):$(id -g)")
# HOME: package.sh refuses a package that contains the build's home folder.
"$engine" run --rm "${user[@]}" -v "$PWD:/src" -v "$PWD/out/release:/src/out" -w /src \
    -e HOME=/home/build -e GOW3_PGO="${GOW3_PGO:-off}" -e GOW3_LTO="${GOW3_LTO:-ON}" \
    -e CPLUS_INCLUDE_PATH=/src/gpu/third_party/xbyak \
    "$image" bash -c 'bash build.sh && packaging/linux/package.sh "$1"' build-release "$version"
