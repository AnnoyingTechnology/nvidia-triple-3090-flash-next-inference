# References

- Strata engine: https://github.com/Niko1221/Strata at `99f3dbd0b21d1401b3769e0c0d963913607f380b`
  (layer split: `docs/MULTI_GPU.md`; memory tiers: `docs/DETAILS.md`).
- llama.cpp reference: https://github.com/ggml-org/llama.cpp at `3cf03257f219afbe7334045ff7c6a06ac68c627d`.
- Target and projector: https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF at
  `ed59f92082b1e93c0e96d60a8b11aab089b52f09`.
- MTP head source: https://huggingface.co/Qwen/Qwen3.8-Flash-Next at
  `de4b8e4d43b917e7706784d8bb445c9af86a3540` (only the MTP tensors are range-fetched).
- Evaluator: https://github.com/LiveCodeBench/LiveCodeBench at `28fef95ea8c9f7a547c8329f2cd3d32b92c1fa24`.
- Frozen RTX 4090 baseline (Ulmus): https://github.com/AnnoyingTechnology/nvidia-4090-flash-next-inference
  at `c91d0787dd43f82b16d78c74c8f9ce99b2ea91ef`; this repository derives from it.
- Same host's Qwen3.8-27B vLLM profile: https://github.com/AnnoyingTechnology/nvidia-dual-3090-llm-inference
