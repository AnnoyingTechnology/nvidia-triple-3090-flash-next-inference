#!/usr/bin/env bash
# Native build for the 3x RTX 3090 / i7-6900K host (no Docker on that host).
# Same pins, CMake options and targets as Dockerfile + Dockerfile.owner-api, adapted to:
# distribution CUDA 12.4 with GCC 13 as host compiler (CUDA 12.4 rejects GCC 14), SM86, AVX2 host
# (ggml native; Strata picks its AVX2 expert kernels at run time), and a Python 3.10 venv so the
# hash-locked API wheels of api-requirements.lock install unchanged.
# The single-GPU lend-VRAM patch is deliberately NOT applied: it refuses multi-GPU operation.
set -euo pipefail
task_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_source="$task_root/upstream/strata"
task_sha=99f3dbd0b21d1401b3769e0c0d963913607f380b
task_llama=3cf03257f219afbe7334045ff7c6a06ac68c627d
task_arch=${STRATA_CUDA_ARCH:-86}
task_jobs=${STRATA_BUILD_JOBS:-$(nproc)}
task_build=${STRATA_BUILD_ROOT:-$task_root/build}
export CC=gcc-13 CXX=g++-13 CUDAHOSTCXX=g++-13
task_uv=${UV:-$(command -v uv || echo "$HOME/.local/bin/uv")}

fetch() {  # url output
    if command -v curl >/dev/null; then
        curl --fail --location --retry 3 --output "$2" "$1"
    else
        wget --tries=3 --output-document "$2" "$1"
    fi
}

mkdir -p "$task_root/upstream" "$task_root/results" "$task_root/packs" "$task_root/mtp" "$task_build"
if ! test -d "$task_source/.git"; then
    git init "$task_source"
    git -C "$task_source" remote add origin https://github.com/Niko1221/Strata.git
    git -C "$task_source" fetch --depth 1 origin "$task_sha"
    git -C "$task_source" checkout --detach FETCH_HEAD
fi
test "$(git -C "$task_source" rev-parse HEAD)" = "$task_sha"
test -z "$(git -C "$task_source" status --porcelain --untracked-files=no)"
if ! test -d "$task_source/ref/llama.cpp/gguf-py"; then
    fetch "https://github.com/ggml-org/llama.cpp/archive/$task_llama.tar.gz" "$task_root/upstream/llama-source.tar.gz"
    mkdir -p "$task_source/ref/llama.cpp"
    tar -xzf "$task_root/upstream/llama-source.tar.gz" --strip-components=1 -C "$task_source/ref/llama.cpp"
fi

# Python: the Ulmus image ran Ubuntu 22.04's Python 3.10; keep that ABI for the locked wheels.
if ! test -x "$task_source/.venv/bin/python"; then
    "$task_uv" venv --python 3.10 "$task_source/.venv"
fi
export VIRTUAL_ENV="$task_source/.venv" PATH="$task_source/.venv/bin:$PATH"
export STRATA_GGUF_PY="$task_source/ref/llama.cpp/gguf-py"
"$task_uv" pip install --requirement "$task_source/requirements.txt"
"$task_uv" pip install --require-hashes --only-binary=:all: --requirement "$task_root/api-requirements.lock"

cd "$task_source"
cmake -S . -B "$task_build/strata" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES="$task_arch" -DCMAKE_CUDA_HOST_COMPILER=g++-13 -DSTRATA_BUILD_TESTS=OFF \
    -DSTRATA_BUILD_CONVERSATION_TESTS=ON -DSTRATA_PARITY_PROMPT_ATTN=ON \
    -DSTRATA_MMQ_KQUANTS=ON -DSTRATA_GGML_DIR="$task_source/ref/llama.cpp"
cmake --build "$task_build/strata" -j "$task_jobs" --target \
    strata strata-device ple_reader_test pinned_shared_test native_expert_parity \
    qsa_prompt_attn_parity conversation_cache_test conversation_memory_test
cmake -S tools/vision -B "$task_build/vision" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DLLAMA_DIR="$task_source/ref/llama.cpp" \
    -DSTRATA_VISION_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="$task_arch" -DCMAKE_CUDA_HOST_COMPILER=g++-13
cmake --build "$task_build/vision" -j "$task_jobs" --target strata-vision
cmake --build "$task_build/strata" -j 2 --target coupled_draft_test sampler_parity
python -m unittest serve.test_structured
sha256sum "$task_build/strata/strata" "$task_build/vision/bin/strata-vision" | tee "$task_root/results/build-native-sha256.txt"
