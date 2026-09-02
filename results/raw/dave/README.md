# results/raw/dave: the local fleet, 2026-09-02

Clean rows:
- `judgment-whale.jsonl`, `mission-whale-final.jsonl` (and `mission-whale.jsonl`, `mission-whale-v61.jsonl`
  for v6.0 and pre-final v6.1): the vLLM endpoint, its own process, never shared.
- `judgment-local-v61.jsonl` rows for gemma-e4b, gemma-12b, gemma-26b-a4b, gemma-31b, and
  `mission-local-v61.jsonl` rows for gemma-12b and gemma-26b-a4b with trace timestamps BEFORE
  16:45Z: one series, one server at a time, on the earlier v6.1 scorer.

Contaminated (kept, renamed, not used): everything from card 1 after 16:45Z. The first local series
was stopped at 16:45Z but its shell kept running; its later arms killed and replaced the final
series' llama-server on the same port under live clients, and the sed that renamed the output files
was read by that still-running shell. So: the `qwen-q4km-*` rows in `mission-local-v61.jsonl` and
`judgment-local-v61.jsonl` are NOT qwen (the server on the port was gemma); `*-final.CONTAMINATED.*`
carry rows whose server is not knowable; gemma-e4b's final-series mission runs died under the
client; the 26B final-series server was killed while loading. Lesson banked in the private record:
a stopped task is not a dead process; verify by process list before starting the next series.
