#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Starts a release tarball on clean systems: is everything it needs really inside?
#   packaging/linux/smoke-test.sh dist/gravityrush-pc-<version>-x86_64.tar.gz
# Each system is a fresh container with only what the README asks of a player's system (Vulkan
# loader and a driver, libX11, FreeType): Ubuntu 24.04 has the oldest glibc the release supports
# (2.39), Debian 13 has the glibc of SteamOS 3.7/3.8 (2.41). The runtime has to load there and
# pass its own Vulkan check (--vulkan-only, on Mesa's software driver). A tarball built on a
# development machine fails here at the first library the container does not have (issue #1).
# build-release.sh runs this before it keeps a tarball. GOW3_SMOKE_IMAGES replaces the systems.
set -euo pipefail
tarball=$(readlink -f "${1:?usage: packaging/linux/smoke-test.sh TARBALL}")
engine=${CONTAINER_ENGINE:-$(command -v podman || command -v docker || true)}
[[ -n $engine ]] || { echo 'Need podman or docker.' >&2; exit 1; }
read -r -a images <<< "${GOW3_SMOKE_IMAGES:-docker.io/library/ubuntu:24.04 docker.io/library/debian:13-slim}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$tarball" -C "$work"
app=$(echo "$work"/*/)
[[ -x $app/out/gravityrush-runtime ]] || { echo "No out/gravityrush-runtime in $tarball" >&2; exit 1; }

for image in "${images[@]}"; do
    echo "== $image"
    "$engine" run --rm -v "$app:/app:ro" -e DEBIAN_FRONTEND=noninteractive "$image" sh -c '
        set -e
        apt-get update -qq >/dev/null
        apt-get install -y -qq --no-install-recommends libvulkan1 libx11-6 libfreetype6 mesa-vulkan-drivers >/dev/null 2>&1
        mkdir -p "$HOME/.local/share"
        echo "glibc $(ldd --version | sed -n "1s/.* //p")"
        missing=$(ldd /app/out/gravityrush-runtime /app/out/gpu/*.so* 2>&1 | grep -E "not found" | sort -u || true)
        if [ -n "$missing" ]; then echo "$missing"; exit 1; fi
        /app/out/gravityrush-runtime --vulkan-only' < /dev/null ||
        { echo "smoke-test.sh: $(basename "$tarball") does not start on $image" >&2; exit 1; }
done
echo "Starts on: ${images[*]}"
