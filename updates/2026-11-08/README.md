# Strata update — 2026-11-08

Selected: Strata 0.2.12 / engine 0.1.58 at
`146df3c468739147f520ac3816de806f71232571`, native CUDA 12.4, SM86, GCC 13 / AVX2.
The model, IQ3_S weights, IQ4_NL PLE, MTP4, int8 KV, 262,144-token server
context, GPU placement and 225 W/card caps are unchanged. The existing vision
helper is retained byte for byte. No driver upgrade was required.

| Context | Cold prefill before → selected | Change | Decode before → selected | Change |
|---|---:|---:|---:|---:|
| 32K | 2,575.7 → 2,614.8 tok/s | +1.5% | 89.3 → 130.2 tok/s | +45.8% |
| 128K | 3,293.8 → 3,575.2 tok/s | +8.5% | 86.8 → 120.3 tok/s | +38.6% |

These are matched document/question inputs and 512-token low-reasoning speed
cells. Decode is a median of three per context. Baseline cold reads have two
samples per context; the final selected launch has one. The 32K prefill delta
is small and should be treated as approximately flat. Earlier starts of the
same new engine also reproduced the large decode gain. Raw reports and the
[summary](summary.json) retain acceptance counts, output hashes and energy.
There is no periodic telemetry polling; cumulative energy is read at boundaries.

## Selection

The new runtime's 32K prefill chunks lost roughly 24% on the short-context
cell. Capping chunks at 16K recovered prompt performance and the previous
checkpoint reuse granularity. The selected service also sets
`STRATA_PROMPT_ATTN_IMMA=0`, retaining the previous prompt-attention numerical
path. Architecture-specific exact decode optimizations remain enabled.

## Where the decode gain comes from

Same-runtime ablations with 16K chunks and the original new attention default:

| Context | All defaults | Ampere bundle off | Bundle off + HC staging off |
|---|---:|---:|---:|
| 32K | 131.0 | 116.1 | 112.7 tok/s |
| 128K | 124.7 | 106.8 | 98.1 tok/s |

The Ampere bundle contributes 12.8–16.8% relative to its off arm. It includes
multi-row quantized matvec reuse, fused gate/mixer work and verification-window
attention kernels. Staged hyper-connection reads add 3.0–8.9% with that bundle
off. These effects are not additive. Remaining upstream changes were not
isolated. Cache hit rates remain around 99%; this host's mechanism differs
from the single-4090 fetched-expert-cache improvement.

Sources: [architecture defaults](https://github.com/Niko1221/Strata/blob/146df3c468739147f520ac3816de806f71232571/docs/DETAILS.md#rtx-30-series-sm_86-and-tesla-p100-sm_60-bitwise-decode-switches-on-by-default),
[hyper-connection kernels](https://github.com/Niko1221/Strata/blob/146df3c468739147f520ac3816de806f71232571/src/kernels/cuda/fused_gr.cu).

## Validation

- Eight GPU/component checks passed, including IQ3 experts and prompt attention.
- Thirteen structured API unit tests passed; nine live owner-contract checks passed.
- Code: stored reference 29/30, new default attention 28/30, selected attention 29/30.
  Frozen deck, request hashes and sampling match; every answer ended naturally.
  These single-seed stochastic cohorts do not establish a quality gain or loss.
  Identical seeds need not consume identical random sequences across runtimes.
- Vision: 14/15; all natural, no transport errors or output caps.
- Maximum-budget images: new/cached/new passed, zero lend/reclaim events.
- Near-native context: 261,200 prompt + 512 output tokens completed.
- Target/draft/tokenizer/expert-profile/vision artifact identities match baseline.

## Reproduce and deploy

This updates an already-provisioned checkout. Frozen assets remain anchored
to the original `upstream/strata` data tree. Build on the target AVX2 machine:

```bash
systemd-run --user --wait --pipe --collect \
  -p MemoryMax=4G -p MemorySwapMax=0 -p CPUQuota=200% \
  bash "$PWD/updates/2026-11-08/build-engine.sh"
sudo bash updates/2026-11-08/install-selected.sh
sudo systemctl restart qwen3.8-flash-next
```

A fresh process per arm and the same cold-prefix namespace reproduce the six
speed cells (choose a fresh result file):

```bash
X3090_UNIT=qwen3.8-flash-next python3 scripts/context_decode_probe.py \
  --cold-prefix update-20261108 --order 32 128 128 32 32 128 \
  --out results/update-qualification.json
```

The drop-in preserves the base unit's limits, model mutual exclusion and boot
policy. The owner's existing LAN binding is now reflected in source and docs.
Builds are isolated under ignored `updates/20261108`; do not build during a
benchmark. Compilation peaked below 3 GiB in this run. The original binaries,
source and vision helper remain available.

Rollback: stop the unit, move only `90-runtime-update.conf` out of its systemd
drop-in directory, reload systemd and start the unit. Its base unit still selects
the prior runtime/profile. Do not remove the model data or original binaries.

The [export manifest](export-manifest.json) records original and public hashes.
Host paths, real private addresses and per-sample telemetry are redacted from
public evidence. Private prompts/logs and full host inventory are not published.
