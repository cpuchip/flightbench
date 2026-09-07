# Fork main 7ca84fc against the validated pr43 image: no regression (2026-09-07)

Michael, the morning after the maintainer merged five of our PRs (#79, #80, #82, #83, #84) and
fixed the CI job that had been applying nothing: "test the main branch for any regression." The
image under test is the registry's `latest`, built by that CI from main at 7ca84fc
(org.opencontainers.image.revision, created 2026-09-07T19:43Z, digest ea5019aa…). The reference is
the record's shipped-default runs on `qwen38-27b-rtx3090:pr43-6869c80` (docs/v0.28-validation.md on
the cpuchip fork, branch v0.28-validation; flightbench results/raw/v028).

Conditions, held to the record's: fermion (RTX 4090 under WSL2), card 1 pinned by UUID, a fresh
compile-cache volume for this boot (the record's soak passes ran on a persisted cache), the launcher
run inside the container with its log at /tmp/server.log (the record's cohort harness shape), our
shipped default `SPEC=dflash2 CTX=fast DFLASH_TOKENS=7 PREFIX_CACHE=1 INT8_ACT=int8
INT8_LAYERS=mlp|linear_attn|self_attn PREFILL_ATTN=int8 GPU_UTIL=0.90`, and no FIELD patch: main's
launcher sets `draft_sample_method=probabilistic` itself since 0e95195 (the boot log reads
`draft_logits=True`). Card 0 was empty throughout.

## Resolved configuration

The API server's `non-default args` line, flattened to 56 fields and diffed against the qwen-prod
(pr43) production boot: **55 identical, 1 different, and that one is the port** (18020 vs 18021).
Same model tag, KV pin (5,583,457,484 bytes), prefix caching, mamba cache mode align, max_num_seqs 8,
async scheduling, the speculative config with num_speculative_tokens 7 and draft_sample_method
probabilistic, the compilation config. GPU KV cache size 68,605 tokens (1.05x at 65,536), the
record's pool to the token. Boot to health 5 min 24 s on the fresh cache (20:20:32 to 20:25:56Z);
graph capture 1.08 GiB. Health probe (count 1 to 30, greedy) correct.

## Cohort (the record's client: eight real prompts, 1024 tokens, four seeds per arm, 32 rows)

| arm | rows | tok/step row mean (sd) | drafts-weighted | tok/s | mean output |
|---|---:|---|---:|---:|---:|
| main a1, seeds 1-4 | 32 | 3.730 (0.979) | 3.399 | 157.6 | 974 |
| main a2, seeds 5-8 | 32 | 3.858 (0.860) | 3.724 | 163.9 | 955 |
| record soak-p1, seeds 1-4 (pr43) | 32 | 3.789 (0.906) | 3.476 | 159.9 | 944 |

Per-prompt means, main a1 against the record's soak-p1 (same seeds): 3.70/4.02, 2.87/2.98,
2.19/2.28, 4.49/4.39, 4.79/4.73, 4.82/4.70, 3.34/3.46, 3.64/3.75. The hard prompt (2) and the easy
ones (4, 5) sit in the same places.

Paired by (seed, prompt), main a1 against soak-p1: n=32, mean difference **-0.059 tok/step, SE
0.072, t -0.82**. Across both arms against the record: tok/step +0.005, drafts-weighted +0.086,
tok/s -0.6. The record's five soak passes are bit-identical replays of one another (fixed seed,
persisted cache), so their pass-to-pass spread is not a noise estimate; the paired row-level test
is the one that carries the verdict, and it cannot see a difference.

Engine's own metric, 10 s windows over the whole session (TTFT ladder plus the 64 rows): n=52, mean
acceptance length **3.618**, median 3.665, sd 0.967. The record's shipped-default windows during the
agent runs read 3.60 to 3.86.

## TTFT ladder (the record's ttft.py: cold first request, two warm repeats, thinking off and on)

| prompt tokens | thinking | main cold / warm TTFT (s) | record cold / warm | main decode tok/s | record decode |
|---:|---|---|---|---:|---:|
| 1458 | off | 1.071 / 0.146 | 1.047 / 0.145 | 112 | (short streams read low) |
| 1498 | on | 0.332 / 0.328 | 0.334 / 0.165 | 145 | 146 |
| 4893 | off | 0.839 / 0.212 | 0.811 / 0.212 | 107 | |
| 4933 | on | 0.828 / 0.161 | 0.837 / 0.148 | 139 | 140 |
| 19883 | off | 3.550 / 0.218 | 3.494 / 0.217 | 100 | |
| 19923 | on | 3.834 / 0.250 | 3.772 / 0.239 | 124 | 125 |

Cold prefill and the warm prefix-cache hit match the record at every size; the prefix cache hits at
19,883 tokens on main as it did on pr43. Time to first content in thinking mode varies with the
sampled reasoning length and is not comparable row for row.

## Verdict, and its caveat

**Main at 7ca84fc shows no regression against the validated pr43 image at the shipped default on
this box**: identical resolved configuration and KV pool, acceptance and throughput inside the paired
test's noise, TTFT at parity. One boot, one card, a fresh cache; the record's caution stands that a
bench row without its compile-cache state is not reproducible (gotcha 53), so this is parity of the
pool and of the cohort, not a claim about every trajectory. Two things main carries that the
validated image did not: probabilistic draft sampling from the launcher (no FIELD patch needed), and
`.env.example` now defaults to `SPEC=mtp` (the launcher default), which is why the shipped default
must be stated explicitly.

## Files

- `boot-lines.txt`: the resolved args line, the KV cache size line, draft_logits, graph capture.
- `cohort-main-a1.txt`, `cohort-main-a2.txt`: the client's rows (per-position acceptance deltas
  included).
- `ttft-results.jsonl`, `ttft-run.log`: the ladder.
- `compare.py`: the comparison against results/raw/v028/soak-default.txt.
- `launch-main-arm.sh`, `run-arm.sh`: the harness (key by env file; the client injected as base64,
  since `docker cp` from Git Bash mangles one side of the path whichever way MSYS conversion is set).
