# Checkpoint - 2026-10-04 (Europe/Paris)

## Selected and deployed

- Profile `x3090-iq3s-256k-gpu12-vision0`: two-stage layer split on GPU1+GPU2, resident vision on
  GPU0, GSQ IQ3_S, int8 KV in VRAM, MTP 4, low reasoning, 262,144 tokens, 225 W on every card.
- Service `qwen3.8-flash-next.service` (installed from `systemd/`, **enabled at boot**), loopback
  `127.0.0.1:19623`. It conflicts with `qwen-3.8-27b.service` (former `qwen-serving.service`,
  LAN port 19622), which starts on demand. At this checkpoint Flash-Next is running.
- Clients: SSH tunnel to local port 19624; OpenCode provider `ai-3090-flash-next/qwen3.8-flash-next`.

## Measured (details in docs/benchmarks-and-quality.md)

Decode 93.7-95.4 (32K), 87.4 (64K), 82.7-84.0 (128K), 77.6 (256K) tok/s; cold prefill
~2,550-3,200 tok/s; practical30 29/30 and vision15 14/15 at low, all natural; maximum-budget images
3/3; API 9/9 on four launches; component checks 8/8. Ulmus remains ~22-26% faster in decode.

## Closed

Three-stage split (no decode gain, slower prompts), one card (27% slower), Q4_K_XL (does not fit
in RAM), peer/helper caches, power above 225 W (policy), CPU workers as an energy lever.

## Host changes made by this campaign

- Deleted three unused LM Studio GGUFs (GLM-4.5-Air, Qwen3.5-122B, Qwen3-Next-80B; 152 GB).
- Installed `docker.io` + `docker-cli` for the isolated grader; daemon without iptables, IP
  forwarding or default bridge. Grader image `x3090/eval:lcb-28fef95` kept.
- Power-limit drop-in unified to 225 W for all cards (previous drop-in backed up by root).
- `qwen-serving.service` replaced by `qwen-3.8-27b.service` (same settings); previous unit and
  drop-in backed up by root.
- No firewall, routing, driver or firmware change.

## Next, if resumed

LAN exposure only with an API key and an image path/URL restriction; a held-out speculation retune;
96K/192K anchors and a near-256K prompt with images.

## Return handoff

The 3x RTX 3090 host is a qualified second Flash-Next host with vision: usable, but slower and less
energy-efficient than the single 4090 at the 225 W policy. Switch models with
`systemctl start qwen3.8-flash-next.service` or `systemctl start qwen-3.8-27b.service`.
