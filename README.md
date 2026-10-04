# NVIDIA triple RTX 3090 Flash-Next inference

This repository records the bounded qualification of **Qwen3.8-Flash-Next on three 24 GiB RTX
3090 cards, an i7-6900K (8 cores, AVX2) and 94 GiB of usable DDR4**, using the target, workloads
and acceptance rules of the frozen
[single RTX 4090 campaign](https://github.com/AnnoyingTechnology/nvidia-4090-flash-next-inference)
("Ulmus"). The selected two-stage layer split decodes **93.7-95.4 tok/s at 32K, 82.7-84.0 at
128K and 77.6 at 256K**, reads cold prompts at **~2,550-3,200 tok/s**, and scores **29/30**
executable DevOps canaries and **14/15** images at low reasoning, every answer completed naturally.

The owner's hypothesis - three cards keep the experts on GPUs and beat the 4090 - does not hold at
the 225 W card policy. The split holds ~99% of the routed experts in VRAM, so the CPU and PCIe
stop mattering, but each Ampere layer is slower than Ada's and a layer split adds no parallelism
for one sequence: decode is **~22-26% below Ulmus** and cold prompt reads take **~1.4-1.8x** as
long, at ~1.8x the board energy per token. This is documented rather than hidden.

The result uses the GSQ IQ3_S target with its IQ4_NL n-gram table, verified MTP speculation (four
draft tokens), int8 KV fully in VRAM, the BF16 vision encoder resident on its own card, the native
262,144-token limit and pinned [Strata](https://github.com/Niko1221/Strata) built natively for SM86.
All experts and the n-gram table stay in RAM (pinned / mlocked): there is no disk decode tier.

## Result

`qwen3.8-flash-next.service` exposes model `Qwen3.8-Flash-Next` (alias `x3090`) on
**`127.0.0.1:19623` only**. Remote clients use an SSH tunnel; Strata's server accepts image file
paths and fetches image URLs, so it is not published unauthenticated on the LAN. The service is
mutually exclusive with the host's
[Qwen3.8-27B vLLM service](https://github.com/AnnoyingTechnology/nvidia-dual-3090-llm-inference)
(`qwen-3.8-27b.service`, port 19622), which needs the same cards and RAM: starting either stops
the other first. The 27B service remains the boot default.

| Selected setting | Value |
|---|---|
| Engine stages | GPU1 layers 0-24, GPU2 layers 25-47 + head + MTP (both PCIe 3.0 x16) |
| Vision | GPU BF16 encoder resident alone on GPU0 (PCIe 3.0 x8, also the desktop card), 4,096 image tokens |
| Target | GSQ-RCO IQ3_S, release IQ4_NL n-gram table in mlocked RAM |
| Expert residency | 17,557 of 24,576 experts cached in VRAM (~99.1% of routed mass); 97.6-98.5% decode hit rate |
| Speculation | MTP, 4 draft tokens, min-p 0.7, Q2_0 draft experts |
| KV | int8, all 262,144 positions in VRAM (no host KV streaming) |
| Sampling | Low reasoning; T 1, top-p 0.95, top-k 20, min-p 0, presence 0, repetition 1 |
| CPU pool | 7 workers on 8 cores, AVX2 kernels selected at run time |
| Power | 225 W on every card (owner policy) |

Matched with Ulmus: the 32K/64K/128K documents and every 32K/128K request hash are identical to
the Ulmus ABBA cells. Fixed 512-token low-reasoning performance cells, medians of three per launch:

| Context | Prefill, cold read | Decode | Ulmus decode |
|---|---:|---:|---:|
| 32K | **2,528-2,573 tok/s** (31,803 tokens, 12.4-12.6 s) | **93.7 / 95.4 tok/s** | 120.10 |
| 64K | 2,707 tok/s (48,187 new tokens, 17.8 s) | **87.4 tok/s** | not measured |
| 96K | not measured | ~85 (interpolated) | not measured |
| 128K | **3,140-3,200 tok/s** (113,723 new tokens, 35.5-36.2 s) | **84.0 / 82.7 tok/s** | 112.55 |
| 192K | not measured | ~80 (interpolated) | not measured |
| 256K | 2,938 tok/s (261,179 tokens, 88.9 s) | **77.6 tok/s** | not measured |

Ulmus reads the same 32K and 128K prompts at ~4,650 tok/s. Follow-up questions on a cached
prefix read only their new tokens (about 15K here: 8.6 s at 32K, 10.3 s at 128K, 14.0 s at 256K).
The service launch reproduced 2,563 tok/s prefill and 96.5 tok/s decode on the 32K cell.

| Quality, low reasoning | 3x RTX 3090 | Ulmus selected |
|---|---:|---:|
| Practical30 executable DevOps/Python canaries, seed 42 | **29/30**, all natural | 29/30 |
| Practical30 median completed-answer time | 9.04 s | 8.62 s |
| Vision15 content / strict JSON | **14/15 / 14/15**, all natural | 14/15 |
| Vision15 median first token, new image | 2.18 s | 1.68 s |
| Maximum-budget 2048x2048 images, new / cached / new | 3/3: 7.1 / 0.16 / 7.0 s | 3/3: 3.7 / 0.11 / 3.7 s |
| API contract checks | 9/9 on four launches | 9/9 |

## Bandwidth reference and remaining headroom

Measured host-to-device bandwidth is 11.7 GB/s (GPU1), 11.0 GB/s (GPU2) and 5.8 GB/s (GPU0, x8),
against 26.9 GB/s on Ulmus. A 1 GiB sequential read measured 14.07 GB/s on one thread and
52.05 GB/s on eight cores (synthetic, not inference bandwidth). Neither limits the selected
decode: Strata predicts and the run confirms ~0.52 ms per layer, ~26 ms per speculative window,
with both stage cards at their power cap (1.70-1.92 GHz of 2.1). During a cold 256K read the
engine keeps about one core busy and the CPU package draws ~32 W.

The remaining hardware lever would be power above 225 W, which owner policy excludes as
overclocking. A third pipeline stage holds every expert yet cannot shorten the window. One card
alone keeps ~8,800 experts and leans on the AVX2 pool over PCIe 3. No credible large lossless
gain remains on this machine for one sequence.

## Optimization ladder

| Decision | Measured result | Integrity boundary |
|---|---:|---|
| One card (GPU1) with vision on GPU0, KV streaming past 32K | 72.6 / 65.6 tok/s at 32K / 128K; 128K read 63.9 s; 241 W | Same requests and target; Ulmus-equivalent one-card layout |
| **Two-stage split GPU1+GPU2 (selected)** | **93.7 / 84.0 tok/s, +29% / +28%; 128K read 35.5 s; ~365 W** | Expert set ~99% resident; second launch 95.4 / 82.7 |
| Three-stage split GPU1, GPU0, GPU2 | 93.1 / 86.6 tok/s; 32K read 15.5 s, 128K 44.5 s; 457 W | Rejected: decode unchanged, prompt reading ~25% slower, +90 W |
| Vision resident on GPU0 instead of Ulmus's lend-VRAM swap | No cache memory lent; ordinary images +0.5 s vs Ulmus | Lend-VRAM patch refuses multi-GPU; vision quality unchanged at 14/15 |
| int8 KV in VRAM instead of host streaming | No host KV; MemAvailable >= 10.75 GiB at 256K | Same attention values; capacity, not speed, decision |
| Q4_K_XL target | Not run | Excluded: Strata pins all experts in RAM (~103 GiB on Ulmus) above 94 GiB |
| Peer tier / helper expert caches | Not run | Peer tier needs P2P (absent); helper caches are documented slower than the CPU pool |

Board energy per decoded token at 32K is 3.3 J (one card), 3.9 J (selected), 4.9 J (three stages)
and 2.2 J on Ulmus. Power is summed over all three boards, including the vision/desktop card.

## Correctness and qualification

The native SM86 build passes **8/8 component checks**: sampler, PLE reader, pinned shared memory,
coupled draft, conversation cache and memory, QSA prompt attention, and IQ3_S expert parity on the
real weights (AVX2 kernels against ggml, GPU dequantization bit-identical to ggml). The isolated
grader passes its positive/negative controls before any model call, and every practical30 case has
its own controls. The practical30 deck hash equals the Ulmus deck (`03b7d02e...`).

Every evaluation binds to the running service through provenance capture: systemd invocation,
engine and vision binary hashes, artifact identities, rendered config and chat template. The
different single practical30 failure (`path-route` here, `literal-endpoint` on Ulmus) sits inside
the original IQ3 seed spread of 28/29/30 and is not a resolved quality difference. Vision fails the
same `invoice` typing case as Ulmus.

## What might still be left

1. LAN service exposure needs an API key and a server-side refusal of image file paths and
   URLs before it is reasonable; until then clients use the SSH tunnel.
2. Speculation retuning for a GPU-bound verify (window length versus acceptance) is the only
   untested software lever; the Ulmus short sweeps failed confirmation, so it needs a held-out deck.
3. 96K and 192K speed, and a combined near-256K prompt with images, are not measured.
4. Headless operation would free the desktop's VRAM and RAM on GPU0; cleanup, not a speed gain.
5. Concurrent c2 execution is unqualified; requests queue FIFO.

## Quick operations

```bash
sudo systemctl start qwen3.8-flash-next.service    # stops qwen-3.8-27b.service first
curl -fsS http://127.0.0.1:19623/health
python3 owner_api_check.py --profile x3090-iq3s-256k-gpu12-vision0 --vision --out results/api-check.json
sudo systemctl start qwen-3.8-27b.service          # back to the 27B vLLM API
```

From a client machine:

```bash
ssh -N -L 127.0.0.1:19624:127.0.0.1:19623 <user>@<host-address>
curl -fsS http://127.0.0.1:19624/v1/models
```

## Production invocation and settings

`scripts/x3090_runtime.py` renders the checkout-relative profile into an absolute runtime config;
the server then runs this engine command with `CUDA_DEVICE_ORDER=PCI_BUS_ID` and
`CUDA_VISIBLE_DEVICES=1,2`:

```bash
build/strata/strata --serve --pack packs/iq3s \
  --native models/gsq-iq3_s/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf \
  --expert-profile upstream/strata/data/expert-profile.bin --expert-cache auto --ple-io ram \
  --prefill auto:32768 --spec 4 --spec-min-p 0.7 --mtp mtp/rt --max-context 262144 --kv int8 \
  --pool-workers 7 --stats --vision --adapt-swaps 24 --layer-split auto
```

The vision encoder runs separately on GPU0:
`build/vision/bin/strata-vision --mmproj <BF16 mmproj> --model <IQ3_S shard 1> --gpu --threads 8 --max-tokens 4096`.

| Setting | Purpose |
|---|---|
| `"gpu": [1, 2]`, `--layer-split auto` | Two stages on the x16 cards; auto chose K=25 to maximize cached routed mass |
| `vision.cuda_device: 0` | Keeps the encoder off the stage cards, so no expert-cache memory is lent per image |
| `--ple-io ram` | Locks the 28.8 GB n-gram table in RAM; no SSD read on the decode path |
| `--prefill auto:32768` | Auto-sized; settles at 16,384-token chunks because a 32K chunk would borrow too many cache slots |
| `--spec 4 --spec-min-p 0.7`, `--adapt-swaps 24` | Ulmus-selected speculation and adaptation batch, unchanged |
| `--pool-workers 7` | One worker per physical core but one, as on Ulmus (11 of 12) |
| No `--kv-resident` | All KV in VRAM; host RAM is the scarce resource on this machine |
| `LimitMEMLOCK=infinity`, `MemorySwapMax=0`, `MemoryMax=88G` | Pinned arena and mlocked table; nothing of the engine may swap |
| `--port 19623`, loopback host | Unauthenticated API kept off the LAN |

## Model and quality contract

Target `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF@ed59f92082b1e93c0e96d60a8b11aab089b52f09`
(IQ3_S shards and BF16 projector, SHA-256 verified by `scripts/prepare_models.py`); MTP from
`Qwen/Qwen3.8-Flash-Next@de4b8e4d43b917e7706784d8bb445c9af86a3540`, packed with Q8 projections and
Q2_0 experts. Strata `99f3dbd0b21d1401b3769e0c0d963913607f380b`, llama.cpp reference
`3cf03257f219afbe7334045ff7c6a06ac68c627d`. IQ3_S, int8 KV and the quantized draft are
quality-relevant boundaries relative to the full-precision release; published paired full-size
values are in [QUALITY-REFERENCE.json](QUALITY-REFERENCE.json). No local full-size reference is
run, and full-size parity is not claimed.

The server advertises 262,144 tokens; OpenCode declares 253,952 context / 245,760 input / 8,192
output. A cold 261,179-token prompt completed with ~10.75 GiB of host RAM still available.
Capped outputs are never scored; the 512-token cells above are performance-only.

## Documentation

- [Benchmarks and quality](docs/benchmarks-and-quality.md): every probe, protocol and limitation.
- [Architecture](docs/architecture.md): hardware, pins, build, placement and memory.
- [Operations](docs/operations.md): build, preparation, services, switching, clients, evaluations.
- [References](docs/references.md): upstream sources and pinned revisions.
- [Checkpoint](CHECKPOINT.md): current state and return handoff.

Sanitized JSON evidence is under `results/public/` ([placement summary](results/public/placement-20261004-summary.json)). Model weights, builds,
virtual environments, logs and credentials are intentionally excluded.
