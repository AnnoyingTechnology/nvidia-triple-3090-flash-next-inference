# Operations

## Build and prepare

On the 3x RTX 3090 host, as the checkout owner (no Docker needed for the engine):

```bash
bash scripts/build_native.sh                  # Strata at the pin, SM86, Python 3.10 venv (~13 min)
python3 scripts/prepare_models.py             # 84.5 GB of pinned GGUFs, hash-verified, resumable
bash scripts/prepare_packs_native.sh mtp      # MTP tensors range-fetched, Q2_0 draft runtime
bash scripts/prepare_packs_native.sh pack     # native IQ3_S pack and tokenizer
```

Allow about 105 GB of free disk for models, MTP sources, pack, build and virtual environment.
`scripts/check_native_components.py --gpu 1` runs the component checks while no service owns GPU1.
`scripts/job.sh <name> <command...>` runs any long step detached with `results/jobs/<name>.{log,pid,done}`.

## Services

```bash
sudo bash scripts/install_services.sh         # renders systemd/*.service.in, daemon-reload, verify
sudo systemctl enable qwen3.8-flash-next.service   # boot default on this host
```

`qwen3.8-flash-next.service` and `qwen-3.8-27b.service` declare `Conflicts=` on each other and an
ordering, so `systemctl start` of either stops the other before starting; measured switch: Flash-Next
stopped in 3 s and the 27B API process started ~2 minutes later. Flash-Next is ready about 2 minutes after start
(weights loaded, n-gram table locked in ~29 s, caches filled). Its `ExecStartPre` renders the runtime
config into `results/runtime/` and records the launch in `results/launches/`.

The 27B unit carries the former `qwen-serving.service` settings unchanged (renamed, with the
`Restart=always` drop-in folded in). Its profile and evidence live in the
[dual-3090 repository](https://github.com/AnnoyingTechnology/nvidia-dual-3090-llm-inference).

## Clients

The Flash-Next API listens on `127.0.0.1:19623` only. A client keeps an SSH tunnel, for example a
systemd user unit running `ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30
-L 127.0.0.1:19624:127.0.0.1:19623 <user>@<host-address>` with `Restart=always`, and points an
OpenAI-compatible provider at `http://127.0.0.1:19624/v1`. OpenCode entry (model `id` is the server's
model name):

```json
"ai-3090-flash-next": {
  "npm": "@ai-sdk/openai-compatible",
  "name": "Qwen3.8 Flash-Next (3x RTX 3090)",
  "options": {"baseURL": "http://127.0.0.1:19624/v1", "timeout": 600000},
  "models": {"qwen3.8-flash-next": {
    "id": "Qwen3.8-Flash-Next", "attachment": true, "reasoning": true, "tool_call": true,
    "modalities": {"input": ["text", "image"], "output": ["text"]},
    "interleaved": {"field": "reasoning_content"},
    "options": {"reasoningEffort": "low", "temperature": 1, "top_p": 0.95, "top_k": 20},
    "variants": {"off": {"reasoningEffort": "none", "temperature": 0.7, "top_p": 0.8, "presence_penalty": 1.5},
                 "low": {"reasoningEffort": "low"}, "medium": {"reasoningEffort": "medium"},
                 "high": {"disabled": true}, "xhigh": {"reasoningEffort": "xhigh"}},
    "limit": {"context": 253952, "input": 245760, "output": 8192}}}}
```

Only one of the two models is served at a time; the client entry of the stopped one simply fails.

## Experiments and evaluations

`run_native.sh <profile>` (root) starts an alternative profile as the transient unit `flashnext-x3090`
and refuses while either model service, the unit itself or a foreign GPU process is active;
`stop_native.sh` stops it. Never measure while building or downloading.

Evaluations bind to the running unit when `X3090_UNIT` names it (`qwen3.8-flash-next` for the
service, `flashnext-x3090` for experiments):

```bash
X3090_UNIT=qwen3.8-flash-next python3 scripts/context_decode_probe.py --context-k 32 128 --out results/decode.json
python3 scripts/prepare_practical30.py && sudo bash scripts/build_grader_x3090.sh
sudo X3090_UNIT=qwen3.8-flash-next ULMUS_GRADER=x3090/eval:lcb-28fef95 python3 practical_eval.py \
  --cases eval/practical30-v2-cases.jsonl --effort low --seed 42 --tokens 32768 --label low --out results/p30.json
python3 vision_compare.py --backend local --model x3090 --effort low --out results/vision15.json
```

The grader needs Docker; on this host the daemon runs with `iptables`, `ip6tables` and `ip-forward`
disabled and no default bridge (the grader uses `--network none`; its image builds with `--network host`).

## Public evidence

`python3 scripts/export_public_x3090.py` exports the allowlist to `results/public/` without telemetry,
local paths or private addresses and writes the placement summary; `python3 scripts/check_public.py`
verifies the tracked surface, links and export checksums before a commit.

## Rollback

`sudo systemctl start qwen-3.8-27b.service` returns the host to the 27B API. Removing the Flash-Next
setup: `systemctl disable --now qwen3.8-flash-next.service`, delete its unit, and remove the checkout
(models, pack, MTP and build are inside it).
