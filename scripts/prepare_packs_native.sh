#!/usr/bin/env bash
# Native equivalent of prepare_packs.sh for the 3x3090 host: same pinned Strata tools and arguments,
# run from the checkout's venv instead of the Ulmus image.
# usage: prepare_packs_native.sh [mtp|pack|all]   (mtp needs no target GGUF; pack needs both shards)
set -euo pipefail
task_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_step=${1:-all}
task_source="$task_root/upstream/strata"
export PATH="$task_source/.venv/bin:$PATH" STRATA_GGUF_PY="$task_source/ref/llama.cpp/gguf-py"
cd "$task_source"
test "$(git rev-parse HEAD)" = 99f3dbd0b21d1401b3769e0c0d963913607f380b
mkdir -p "$task_root/packs/iq3s" "$task_root/mtp"
if test "$task_step" = mtp || test "$task_step" = all; then
    python tools/mtp_fetch.py fetch --out "$task_root/mtp"
    python tools/mtp_fetch.py verify --out "$task_root/mtp"
    python tools/mtp_pack.py --src "$task_root/mtp" --experts q2_0 --out "$task_root/mtp/mtp-q2_0.gguf"
    python tools/mtp_rt.py --gguf "$task_root/mtp/mtp-q2_0.gguf" --out "$task_root/mtp/rt"
fi
if test "$task_step" = pack || test "$task_step" = all; then
    python tools/iq_pack.py \
        --gguf "$task_root/models/gsq-iq3_s/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf" \
        --out "$task_root/packs/iq3s"
fi
