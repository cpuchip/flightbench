# flightbench

**Test models like it's 1969.**

A falsifiable tool-calling and judgment benchmark for local LLMs, staged as
Apollo-era mission control. The model sits on the CapCom loop; the benches
feed it telemetry, procedures, anomalies, and authority conflicts; a
deterministic simulator scores every decision from the actual tool-call
trace. No AI judges, no vibes: a call either fired with the right arguments
at the right time or it did not.

This started as a one-night question (is a voice-agent fine-tune actually
better than its base model?) and grew into an instrument. The goal is not a
leaderboard where our favorite model wins. The goal is a bench where every
model we can run today fails somewhere legible, so that when new models
ship, we can measure growth instead of collecting confirmations. As of the
first published board: nobody goes GREEN on the judgment bench, and the
fleet splits along two axes no single model holds both of.

## The benches

| bench | file | what it measures |
|---|---|---|
| toolbench | `benches/toolbench.py` | baseline tool calling in a friendly domain (restaurant): right tool, right args, no tool-spam, an honesty probe with tools stripped |
| stations | `benches/stations.py` | seven mission-control station checks: go/no-go logging, out-of-limits handling, state tracking ("belay that"), escalation authority, honesty out-of-domain |
| cryo | `benches/cryo.py` | a state machine: the oxygen-tank stir procedure, order enforced per tank, with an Apollo-13-shaped anomaly injected mid-stir. Measures procedure fidelity when the recipe IS given |
| judgment | `benches/judgment.py` | the main event: NO recipe in the prompt (procedures live behind a flight-book tool), opaque data handles so call order emerges from dependencies, and every trap in the data: a stale state vector, a window that misses pad clearance by 4 minutes, a STAND BY that is not a confirm, and Flight ordering a forbidden shortcut |
| codegen | `benches/codegen.py` | the model writes the go/no-go evaluation function from the flight book's constraints; a deterministic oracle runs 14 cases against it, boundaries and precedence included |

Design law, learned the hard way: interlocks stay deterministic; the model
conducts. Sequencing known steps is script work, therefore the benches
score judgment (notice the 122-minute timestamp nobody mentioned, refuse
the shortcut the book forbids, retry on a busy comm loop instead of
aborting) rather than recitation.

## Quick start

Needs Python 3.10+ (stdlib only) and any OpenAI-compatible chat endpoint
that supports tool calls. The included runner drives a local llama.cpp
server:

```bash
bash scripts/run.sh my-model /path/to/model.gguf --think off
# MoE too big for VRAM? keep experts in RAM:
bash scripts/run.sh big-moe /path/to/moe.gguf --server-args "--n-cpu-moe 12"
```

Or point the benches at any endpoint directly (vLLM, LM Studio, a cloud
API):

```bash
BASE=http://127.0.0.1:8000/v1 MODEL=my-model THINK=off python benches/judgment.py
```

Results append as JSONL under `results/raw/`; `scripts/perf_from_log.py`
harvests prefill/decode rates and warm-turn cache reuse from a llama.cpp
server log. Current standings: [results/RESULTS.md](results/RESULTS.md).

## Where this is going

- More scenarios per station, and n>1 per cell (the current board is n=1
  and says so).
- Deep-context variants grounded in NASA SP-4205 (Chariots for Apollo),
  which is public domain and full of real judgment calls with real
  numbers. The harvest list lives in
  [docs/scenario-quarry.md](docs/scenario-quarry.md).
- Coding harnesses through the same discipline: give opencode, Claude
  Code, codex, and friends a launch procedure and a repo, and score the
  trace the same way.
- Whatever you send. If a model beats a station, the right response is a
  harder station; PRs welcome.

## Provenance and method

Built by cpuchip with AI assistance, in one very fun weekend; every score
in RESULTS.md comes from a run on hardware we own, with the raw JSONL and
server logs kept. Methodology notes (pre-registered predictions, the
instrument-ledger habit, why the honesty detector is negation-aware) are
in [docs/methodology.md](docs/methodology.md). The Apollo framing is
affectionate: the era's discipline (flight books, go/no-go polls, the
stir that was routine until it wasn't) turns out to be exactly the shape
you need to test whether a model can be trusted next to real systems.
