# 3x RTX 3090 / i7-6900K checkpoint

Current-state record for the Flash-Next trial on the owner's second R&D machine. The Ulmus
(RTX 4090) deployment is frozen and untouched; its records in this repository are the
comparison baseline. Times are Europe/Paris.

## Host (observed 2026-10-04)

- Intel i7-6900K, 8 cores / 16 threads, AVX2 (no AVX-512); 94.2 GiB usable RAM, 7.5 GiB swap.
- Three RTX 3090 24 GiB (SM86), driver 550.163.01, distribution CUDA 12.4 toolkit, GCC 13 host compiler.
- PCIe 3: GPU0 x8 (also drives the desktop / remote-desktop session), GPU1 and GPU2 x16.
  Topology PHB for every pair, no NVLink. Measured H2D: 11.7 GB/s (GPU1), 11.0 GB/s (GPU2).
- Power limits: **225 W on all three cards** (owner policy: 225 W is the efficiency sweet spot;
  anything higher is treated as overclocking and is out of scope).
- Debian 13. No Docker originally; `docker.io` was installed for the isolated grader only, with
  `iptables`/`ip6tables`/`ip-forward` disabled and no default bridge (grader runs `--network none`).
- The 27B vLLM service that normally owns GPUs 1-2 is stopped for this trial (owner instruction;
  it remains enabled at boot, so a reboot restarts it and collides with this trial).

## Build and assets

| Item | Pin / identity |
|---|---|
| Strata | `99f3dbd0b21d1401b3769e0c0d963913607f380b` (clean, no Ulmus patches) |
| llama.cpp reference | `3cf03257f219afbe7334045ff7c6a06ac68c627d` |
| Native engine (SM86) | sha256 `7ec9f59087aa8e6c009390a17a9976de924f2abb4c66b0d7973ffe9290aee250` |
| Native vision tool | sha256 `fb1d356b9727db5b3ba71c13df52bdada803df9c38f99c703bff97515d558343` |
| Target / projector | GSQ IQ3_S shards + BF16 mmproj at the README pins, all three SHA-256 verified |
| MTP source | `Qwen/Qwen3.8-Flash-Next@de4b8e4d43b917e7706784d8bb445c9af86a3540`, Q2_0 experts |
| Grader image | `x3090/eval:lcb-28fef95` (python:3.10-slim digest pinned, LCB `28fef95`, numpy 2.2.6) |

`scripts/build_native.sh`, `scripts/prepare_models.py`, `scripts/prepare_packs_native.sh`,
`scripts/build_grader_x3090.sh` reproduce this. The single-GPU lend-VRAM patch is not applied:
it refuses multi-GPU operation. Vision instead runs resident on its own card.

Component checks (`scripts/check_native_components.py`, GPU1): **8/8 pass** - sampler, PLE reader,
pinned shared memory, coupled draft, conversation cache/memory, QSA prompt attention, and native
IQ3_S expert parity on real weights (AVX2 kernels vs ggml, GPU dequant bit-identical to ggml).
Grader controls in isolation: correct programs pass, public-only programs fail.

## Serving

`run_native.sh <profile>` (root, for unlimited memlock) starts the transient unit
`flashnext-x3090` as the checkout owner: loopback `127.0.0.1:19623`, `MemoryMax=88G`,
`MemorySwapMax=0`. `stop_native.sh` stops it. Profiles keep relative paths;
`scripts/x3090_runtime.py` renders the absolute config into ignored `results/runtime/`.
Evaluations set `X3090_UNIT=flashnext-x3090` so provenance binds to the unit instead of a container.

Common settings (Ulmus-equivalent unless hardware-specific): GSQ IQ3_S + release IQ4_NL PLE table,
`--ple-io ram` (mlocked), all experts pinned in RAM, low reasoning default, T1 / top-p .95 /
top-k 20, MTP spec 4 / min-p .7, int8 KV fully in VRAM (no host KV streaming), 262144 context,
adapt-swaps 24, **7 pool workers** (8 cores), PCIe fraction probed per card, GPU BF16 vision on
GPU0 (4096-token image budget).

## Measurements

Matched with Ulmus: the 32K/128K decode probe documents and every request hash are identical to
the Ulmus ABBA cells. Fixed 512-token performance cells, not quality evidence.

| Profile (225 W) | 32K decode | 128K decode | 32K cold read | API |
|---|---:|---:|---:|---:|
| Ulmus selected24, 4090 (published) | 120.10 | 112.55 | 6.81 s | 9/9 |
| `gpu12-vision0`: split GPU1+GPU2, vision GPU0 | **93.7** | **84.0** | 12.36 s | 9/9 |

Medians of three cells. In the two-card split, the caches hold 17,557 of 24,576 experts
(~99.1% of routed mass); decode is bound by per-layer Ampere GPU time (~0.52 ms/layer,
~26 ms per window), not by CPU or PCIe. Both stage cards run at their power cap during decode
(1.70-1.92 GHz). Loaded host RAM: cgroup 85.8 GiB current (~12.7 GiB of it reclaimable file
cache), 50.1 GiB anon (pinned arena), 26.8 GiB mlocked PLE; host MemAvailable 12.4 GiB.
Image smoke: correct content, new image 2.56 s to first token, cached 0.08 s.

## Decisions

- Q4_K_XL is not viable here: Strata pins every expert in host RAM (Ulmus measured ~103 GiB for Q4),
  above this host's 94 GiB; a disk tier is excluded.
- Peer tier needs P2P (absent); helper caches (`--expert-cache-device1..3`) are documented slower
  than the CPU pool. Layer split is the multi-GPU mode.
- No power increase above 225 W (owner policy).

## Running now / next

See the README's 3x3090 section for the current selection. Next: three-stage split A/B
(prefill pipelining, full expert residency), then quality qualification (practical30 low,
vision15 low) on the selected placement and sparse long-context anchors.

Rollback for the host: `stop_native.sh`, then `systemctl start qwen-serving.service` restores the
27B vLLM API (about 2.5 minutes to answer).
