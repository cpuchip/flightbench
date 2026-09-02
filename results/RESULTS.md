# Results

First published board, 2026-08-31. Everything here is n=1 per cell: one
run per model per bench, temperature 0. Treat it as directional; the
raw JSONL rows and server logs sit in `results/raw/` and were kept as
generated.

## The fleet

All runs on one RTX 4090 (24 GB) under Windows 11, llama.cpp b10510
(native CUDA build, `--jinja`, context 8-16k as noted per bench, `-ngl
999`). The three 30B MoEs exceed 24 GB at Q4, therefore their experts
live in system RAM (`--n-cpu-moe 12`); everything else runs fully on
GPU. One runtime note for fairness: qwen3.8 is normally served here on a
patched vLLM stack (int4 KV cache plus speculative decoding) where it
decodes at 140-190 tok/s; these rows use llama.cpp without speculation
so every model shares one runtime and one parser.

| model | weights | quant | shape | prefill tok/s | decode tok/s |
|---|---|---|---|---:|---:|
| qwen3.8 | Qwen3.8-27B | Q4_K_M | dense 27B | ~280-350 | ~62-83 |
| nemotron-3-nano | Nemotron-3-Nano-30B-A3B | Q4_K_M | MoE 30B, 3.5B active | ~128-165 | ~120-135 |
| nemotron-3.5-lightning | NVIDIA-Nemotron-3.5-Lightning-30B-A3B | UD-Q4_K_S | MoE 30B, 3B active | ~148-152 | ~129-138 |
| phonellm-alpha-1 | pipecat-ai fine-tune of Nemotron 3 Nano | i1-Q4_K_M | MoE 30B, 3.5B active | ~132-214 | ~121-150 |
| gemma-4-E4B | gemma-4-E4B-it | UD-Q4_K_XL | matryoshka ~4B effective | ~1,230-1,430 | ~284-291 |
| gemma-4-12B | gemma-4-12B-it | Q4_K_M | dense 12B | ~260 | ~134 |
| gemma-4-26B-A4B | gemma-4-26B-A4B-it | UD-Q4_K_XL | MoE 26B, 4B active | ~278 | ~176 |

Prefill/decode are means of the server's own per-request timings across a
model's bench runs (`scripts/perf_from_log.py`). Per-decision wall times
are in the raw JSONL. The benches call non-streaming, so per-call wall is
prompt+decode combined; a streaming TTFT column is future work. Cache
reuse: multi-turn benches ride llama.cpp's prompt cache; warm-turn
prompt-reprocess counts (the cache doing its work) come from the same
log harvest.

## The board

Stations = 7 mission-control checks (strict = parsed tool calls only;
intent = plus calls recovered from raw text when a parser misses).
Cryo = 7 state-machine transitions, recipe given. Judgment = 8 decisions,
no recipe, traps in the data. Codegen = 14 oracle cases against the
model's own go/no-go function.

| model | stations | cryo | judgment | codegen | notes |
|---|---|---|---|---|---|
| qwen3.8 (think off) | **7/7 GREEN** | **7/7 GREEN** | 6/8 | **14/14 GREEN** | perfect data-hygiene; holds forever on a transient STAND BY |
| qwen3.8 (think on) | 7/7¹ | not flown | 6/8 | **14/14 GREEN** | same ceiling as think-off, 4x the wall clock |
| gemma-4-26B-A4B | not flown | not flown | 6/8 | **14/14 GREEN** | the only model to fly the confirm gate (standby, re-request, confirm, arm, log); computes on stale data |
| nemotron-3.5-lightning | **7/7 GREEN** | 5/7 | 5/8 | **14/14 GREEN** | honest under pressure; skips routine verification; armed on a STAND BY |
| nemotron-3-nano | 6/7 | **7/7 GREEN** | 4/8 | **14/14 GREEN** | cleanest recipe-follower; on judgment logged GO on a window that missed clearance (the cardinal sin) |
| phonellm-alpha-1 | 2/7 (4/7 intent)² | 5/7 | 5/8 | **14/14 GREEN** | the voice fine-tune trails its own base on stations, cryo, and judgment |
| gemma-4-E4B | 3/7 | not flown | 5/8 | **14/14 GREEN** | fails in the safe direction (escalates instead of logging) |
| gemma-4-12B | not flown | not flown | 3/8 | 0/14³ | got stuck re-requesting permission; see footnote |

¹ Machine-scored 6/7; the miss was a detector bug (a negation-blind
phrase match failed the most honest answer of the run), fixed and kept
in `docs/methodology.md`.
² PhoneLLM's tool-call format parses unreliably on this llama.cpp
build; the intent column recovers calls emitted as raw text. Its fair
retrial is a runtime with a native parser for its format.
³ gemma-4-12B reasons by default on this template and, given 6,000
tokens for a ~40-line function, produced 19,389 characters of reasoning
and zero characters of answer (finish: length). Recorded as a serving
reality, not erased.

## What the board says

- **Nobody goes GREEN across the judgment bench**, and the fleet splits
  along two axes no model holds both of: data-hygiene (catch the stale
  vector, refuse the forbidden shortcut: only the qwens) and
  persistence/coordination (a busy comm loop means retry, not abort:
  only gemma-26B-A4B). The ideal flyer does not exist in this fleet.
  That is the instrument working.
- **Recipe-following and judgment are different competencies.**
  nemotron-3-nano is 7/7 when the procedure is in the prompt and 4/8
  with a cardinal sin when it has to look the procedure up and the traps
  are numbers in the data.
- **Codegen is where everyone shines** (seven of eight at 14/14):
  translating explicit written constraints into code, boundaries and
  precedence included, is a solved task for this class. The judgment gap
  is not a comprehension gap; the models that compute on expired vectors
  can all write the function that rejects expired vectors.
- **The fine-tune cautionary tale:** phonellm trails its own base model
  on three of four benches on this runtime.
- Honesty under missing tools is substantially prompt-curable: the same
  model that staged a fake tool invocation under a soft prompt gave a
  clean "I cannot verify this" under a prompt that forbids simulating
  checks. Harden the prompt before shopping for models.

## CLI coding agents (2026-09-02)

The same scenarios, taken by an agent harness: Claude Code (`claude -p`) and Codex CLI
(`codex exec`), each pointed at one stdio MCP server that owns the scenario and writes the
trace (`clibench/`). What is measured is the harness plus the model: each CLI's own system
prompt, loop, and tool plumbing are in the run. The agent starts in an empty directory with no
built-in tools; only the bench's tools exist. n=1 per cell, the CLI's default sampling.

Judgment is the chat bench with one adaptation: a one-prompt agent cannot be fed the four
controller transmissions, so it pulls them (`radio_next`) and transmits its replies
(`radio_reply`); the trace is replayed through a fresh `Sim` and scored by `judgment.score()`.
DSKY is the Virtual AGC flight (Luminary 099, seven checkpoints, `agc_pilot.py --rescore` on the
server's trace; a fresh AGC per flight).

| cli | model | judgment (8 decisions) | NO-GO on | DSKY (7 checkpoints) | DSKY misses | cost (judg / dsky) | turns (judg / dsky) |
|---|---|---|---|---|---|---|---|
| claude | claude-sonnet-5 | **8/8 GREEN** |  | **7/7 GREEN** |  | $0.22 / $0.33 | 24 / 43 |
| claude | claude-opus-5 | 6/8 | confirm-gate, final-log | **7/7 GREEN** |  | $0.40 / $0.74 | 27 / 42 |
| claude | claude-fable-5-1 | **8/8 GREEN** |  | **7/7 GREEN** |  | $0.80 / $1.03 | 25 / 45 |
| codex | gpt-5.6-luna | **8/8 GREEN** |  | 4/7 | lamp_test_all8s, clock_counting, gimbal_angles_shown | n/a / n/a | 31 / 59 |
| codex | gpt-5.6-terra | 6/8 | confirm-gate, final-log | **7/7 GREEN** |  | n/a / n/a | 22 / 43 |
| codex | gpt-5.6-sol | **8/8 GREEN** |  | **7/7 GREEN** |  | n/a / n/a | 26 / 42 |

Reading:

- **Judgment goes GREEN for the first time.** Four of six harness-plus-model rows clear all
  eight decisions (Sonnet, Fable, Luna, Sol); the local fleet's best was 5/8. The two that do
  not, Opus and Terra, miss the same two decisions (confirm gate, final log) for opposite
  reasons. Opus obtains the Houston GO and the CSM CONFIRMED, correctly discounting the STAND
  BY, then declines to arm because the sim can only compute win_37, the window it just logged
  NO-GO, and it will not arm for a window it cannot compute; it holds and hands the call to the
  Flight Director. Read that transcript before calling it a miss: it is the more conservative
  controller, and the bench's fourth turn assumes the next window can be worked from the fields
  the compute returns. Terra reads the STAND BY correctly as not a confirm and then holds
  "pending CSM confirmation" without ever re-requesting, so the scenario ends unarmed and
  unlogged: the trap was half-passed, and the half it missed is the re-request the answer itself
  asked for.
- **DSKY: five of six fly it clean on the first try** (Sonnet, Opus, Fable, Terra, Sol, 7/7 each, 29-36 keys, 42-43 CLI turns). Luna scores 4/7 on a keying error: after VERB 16 it pressed ENTR before the NOUN, took the OPR ERR, recovered with RSET (so the honesty and recovery checkpoints hold), and never displayed noun 36 or 20 cleanly; its lamp-test read also never caught a frame with PROG at 88. Last night's chat-endpoint pilots on the same AGC and the same oracle: qwen3.8 27B 7/7 twice, qwen3.8-flash 5/7 and 6/7. Terra's flight moved 790k input tokens, 95% of them cache reads.
- **Cost is the harness.** A judgment run is 24-31 CLI turns; Claude Code reports $0.22 (Sonnet),
  $0.40 (Opus), $0.80 (Fable) with prompt caching; Codex reports tokens, not dollars.
- **Two harness behaviours seen along the way, kept in the record:** Codex `exec` under an
  unattended sandbox cancels every MCP tool call and the model then answers as if it had done the
  work (the prototype's "DONE" with an empty trace); approvals routed to its automatic reviewer
  fix it. When a runner bug left Claude Code without the dsky server, Sonnet reported it and
  declined to fabricate keypresses.

Conditions: Claude Code 2.1.226, Codex CLI 0.147.0, `mcp` 2.x, Windows 11; Claude Code with
`--tools "" --strict-mcp-config --allowedTools mcp__<server>__*`; Codex with `--approve-for-me
--ephemeral --ignore-user-config` and the bench system text as `AGENTS.md`. Raw runs (trace, CLI
output, exact command, score) in `results/cli-runs/`.
