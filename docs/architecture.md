# Architecture

## Hardware, observed 2026-10-04

| Component | Value |
|---|---|
| CPU | Intel i7-6900K, 8 cores / 16 threads, AVX2, no AVX-512 |
| RAM | 94.2 GiB usable DDR4 (quad-channel per owner, not read from firmware), 7.5 GiB swap |
| GPUs | 3x RTX 3090 24 GiB, SM86, driver 550.163.01 |
| Links | PCIe 3.0: GPU0 x8 (desktop and remote-desktop card), GPU1 and GPU2 x16; topology PHB, no NVLink or P2P |
| Measured H2D | 5.8 GB/s (GPU0), 11.7 GB/s (GPU1), 11.0 GB/s (GPU2) |
| Power | 225 W on all three cards, persisted by `nvidia-power-limit.service` |
| OS | Debian 13, distribution CUDA 12.4 toolkit, GCC 13 as CUDA host compiler |

## Pins

| Input | Pin |
|---|---|
| Strata | `99f3dbd0b21d1401b3769e0c0d963913607f380b`, unmodified |
| llama.cpp reference | `3cf03257f219afbe7334045ff7c6a06ac68c627d` |
| Target / projector | `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF@ed59f92082b1e93c0e96d60a8b11aab089b52f09` |
| MTP source | `Qwen/Qwen3.8-Flash-Next@de4b8e4d43b917e7706784d8bb445c9af86a3540` |
| Evaluator | LiveCodeBench `28fef95ea8c9f7a547c8329f2cd3d32b92c1fa24`, `testing_util.py` SHA-256 `b7cb6a8a...` |
| Grader base | `python:3.10-slim@sha256:c1aaf3d03e14944a039a1647e0b3f6f34c6bee517bac6ff380215ee099c4e808` |

| File | Bytes | SHA-256 |
|---|---:|---|
| IQ3_S `00001-of-00002.gguf` | 54,817,524,224 | `4c1eb2ceb4915e1192f4f386021897bde56a97f40a0bb78bb86465e0f7d2aca3` |
| IQ3_S `00002-of-00002.gguf` (IQ4_NL n-gram table) | 28,800,138,432 | `316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113` |
| BF16 mmproj | 907,543,008 | `b1a82259702816a5330d7bd7607cd9676b11780e79ff7348c21103ff3ce49bd0` |

Measured native binaries: engine `7ec9f59087aa8e6c009390a17a9976de924f2abb4c66b0d7973ffe9290aee250`,
vision tool `fb1d356b9727db5b3ba71c13df52bdada803df9c38f99c703bff97515d558343`. A rebuild on other
hardware can produce different hashes; these identify the measured build, not a reproducibility guarantee.

## Build

`scripts/build_native.sh` reproduces the Ulmus Dockerfile's CMake options and targets natively:
SM86, `CC/CXX/CUDAHOSTCXX` = GCC 13 (CUDA 12.4 rejects GCC 14), ggml built native for the host,
Strata's AVX2 expert kernels selected at run time, and a Python 3.10 `uv` virtual environment so
the hash-locked API wheels (`api-requirements.lock`) install unchanged. The Ulmus lend-VRAM patch is
not applied: it refuses multi-GPU operation. The build takes about 13 minutes on this CPU.

## Placement

- **GPU1**: layers 0-24, dense weights, its KV, its expert cache, prompt-path buffers.
- **GPU2**: layers 25-47, output head, MTP draft layer (1,098 MiB), its KV and expert cache.
  The two caches hold 17,557 of the 24,576 profiled experts, about 99.1% of the routed mass.
  One hand-off per verify window crosses host memory; no P2P is needed.
- **GPU0**: the BF16 vision encoder process alone (`vision.cuda_device: 0`), next to the desktop.
- **Host RAM**: all 24,576 experts pinned once (~50 GiB anonymous), the 28.8 GB n-gram table mlocked
  (`--ple-io ram`), and the CPU pool computing the few experts no card holds.
- **Disk**: load source only.

Loaded and idle: GPU0 2.0 GiB, GPU1 23.8 GiB, GPU2 23.7 GiB, 446 MiB free across the stages after
the caches fill. Host MemAvailable is ~11-12 GiB, and at least 10.75 GiB during a 256K prompt.
The unit's `MemoryMax=88G` is a coarse guard only: mlocked n-gram pages stay charged to whichever
cgroup first read the file, so host-wide MemAvailable is the figure to watch.

## Boundaries

- One request at a time; further requests queue FIFO.
- IQ3_S target, int8 KV and a Q2_0-expert draft: quality-relevant quantization boundaries.
- Q4_K_XL does not fit: Strata pins every expert in host RAM (~103 GiB on Ulmus).
- The API is unauthenticated and bound to loopback.
