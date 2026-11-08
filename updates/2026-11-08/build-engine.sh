#!/usr/bin/env bash
# Run on the target AVX2/SM86 host, not on a newer x86 build machine.
set -euo pipefail
task_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
task_run=${STRATA_UPDATE_ROOT:-$task_root/updates/20261108}
export STRATA_SOURCE_ROOT="$task_run/strata"
export STRATA_SOURCE_REV=146df3c468739147f520ac3816de806f71232571
export STRATA_BUILD_ROOT="$task_run/build"
export STRATA_BUILD_RECORD="$task_run/build-engine-sha256.txt"
export STRATA_BUILD_JOBS=2 STRATA_CUDA_ARCH=86-real STRATA_BUILD_VISION=0
export STRATA_VISION_EXE="$task_root/build/vision/bin/strata-vision"
exec bash "$task_root/scripts/build_native.sh"
