# Upstream vLLM fixes backported to the qwen38-27b-rtx3090 fork, 2026-09-08

Three upstream commits rebuilt as fork-style patches and verified on fermion card 1 (RTX 4090, WSL2)
against the fork's main image (7ca84fc, byte-identical to ghcr latest that day), shipped default
`SPEC=dflash2 CTX=fast DFLASH_TOKENS=7 PREFIX_CACHE=1`, int8 activations and prefill attention, fresh
compile cache per boot, the patch applied to the installed tree before the launcher ran.

- `#54282` fe755c889, draft-noise salt: the one that acts here (probabilistic draft sampling is the
  shipped default). `tests.log`: upstream's unbiasedness test fails unpatched, passes patched.
  `cohort-fix-a1/a2.txt` paired against `../main-7ca84fc-2026-09-07/cohort-main-a1/a2.txt` in
  `arms-fix.log`: tok/step 3.784 -> 3.802 pooled (t +0.28), accepted/drafted 0.3629 -> 0.3646.
- `#54374` 5093e4844 and `#54373` d61b6e187: dormant on this hardware and checkpoint pair
  (FlashAttention reports version 2, so the AOT flag is never set; the RoPE layout resolves to the
  same neox default on both sides). `cohort-all3-a1/a2.txt` with all three applied, paired against the
  salt-only arm in `after-arms.log`: t -0.33 and +0.24.
- `after-arms.log` also has the full gumbel test list (18 of 20; the two failures are #53017's tests,
  a stride fix the fork does not carry and cannot hit) and the start of a Docker build of the salt
  branch that the host killed for memory; the build was not completed.

Harness: `launch-fix-arm.sh` (runtime patch + the fork's verify.sh gate + launcher), `arms-chain.sh`,
`pair.py` (rows paired by seed and prompt), `run-salt-tests.sh`, `probe.sh` (FA version), `verify-gate.sh`.
Card 1 was borrowed through the llama-chip node's yield API with a scheduled-task dead-man restore.
