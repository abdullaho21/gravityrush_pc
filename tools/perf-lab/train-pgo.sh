#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# PGO training run: starts an INSTRUMENTED build (GOW3_PGO=generate packaging/linux/build-release.sh
# <version>, unpacked into builds/train) with your normal settings, saves and game folder. The GPU
# library writes its profile every 30 s into pgo/ at the top of the source tree, where
# GOW3_PGO=use packaging/linux/build-release.sh reads it.
#   tools/perf-lab/train-pgo.sh [GAME_FOLDER]      (TRAIN_APP: another unpacked instrumented build)
# Play 10-15 minutes, mostly in busy streets (gravity shifts, fights, flying), then close the window.
# The instrumented build is slower than usual. Deep CPU sleep is blocked meanwhile (with-qos.sh) when
# /dev/cpu_dma_latency is writable: PGO only paid off with it blocked on the machine it was tried on.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
app="${TRAIN_APP:-$here/builds/train}"
[[ -x $app/gravityrush-pc ]] || { echo "train-pgo: missing $app (unpack the instrumented tarball there)" >&2; exit 1; }
mkdir -p "$repo/pgo"
# The build wrote its profile path as /src/pgo/... (inside the build container): map it here.
export GCOV_PREFIX="$repo/pgo" GCOV_PREFIX_STRIP=2
export GOW3_DRAW_PIPE="${GOW3_DRAW_PIPE:-1}"
if [[ -w /dev/cpu_dma_latency ]]; then
    exec "$here/with-qos.sh" "$app/gravityrush-pc" "$@"
fi
exec "$app/gravityrush-pc" "$@"
