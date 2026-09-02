# flightbench for CLI coding agents

The same scenarios, taken by an agent harness instead of a bare chat endpoint: Claude Code
(`claude -p`) and Codex CLI (`codex exec`), each pointed at one stdio MCP server that owns the
scenario and writes the trace. Scoring is the bench's own oracle, run on the trace afterwards.

What is measured is the **harness plus the model**: Claude Code's and Codex's own system prompts,
loops, and tool plumbing are in the measurement, by design. The row is the model id; the column
is the CLI.

## Run

```
pip install mcp                                  # 2.x (MCPServer)
python clibench/run.py --cli claude --model claude-sonnet-5 --bench judgment
python clibench/run.py --cli codex  --model gpt-5.6-luna    --bench judgment
python clibench/run.py --cli claude --model claude-opus-5   --bench dsky --agc-lab <dir with agc_dsky.py, flightbook.md, agc_pilot.py>
python clibench/board.py                          # results/cli-runs/rows.jsonl -> markdown
```

Every run gets a directory under `results/cli-runs/` with the trace, the CLI's raw output, the
exact command, and the score. The agent works in an empty directory with no built-in tools
(Claude Code: `--tools ""`, `--strict-mcp-config`; Codex: the MCP server as `-c` overrides, the
bench system text as `AGENTS.md`).

## The two benches

**judgment** (`benches/judgment.py`, eight decisions). The chat version feeds four controller
transmissions turn by turn. A one-prompt agent cannot be fed, so it *pulls*: `radio_next` returns
the next transmission, `radio_reply` transmits the spoken answer, and the eight sim tools are the
same tools with the same parameters. The trace is replayed through a fresh `Sim` (deterministic,
so the replay reproduces the agent's state) and `judgment.score()` reads the eight decisions.
Deviation from the chat bench, stated: the agent controls pacing, and a reply is only what it
chose to transmit.

**dsky** (Virtual AGC, Luminary 099, seven checkpoints). `press`, `read_display`, `wait`, `done`,
identical to `agc_pilot.py`; the server writes agc_pilot's own trace shape and
`agc_pilot.py --rescore` scores it. A fresh AGC is launched before every flight (README recipe:
detached `yaAGC`, readiness = packets after a RSET stimulus).

## Things learned setting it up

- Codex `exec` cancels every MCP tool call under an unattended sandbox (`-s read-only` or
  `workspace-write` with `approval_policy="never"`): the calls show as "user cancelled" and the
  model answers anyway. `--approve-for-me` (approvals routed to Codex's automatic reviewer under
  the workspace-write sandbox) runs them; so does the full bypass, which this runner does not use.
- Claude Code needs the MCP tools pre-allowed (`--allowedTools "mcp__<server>__*"`) or print mode
  denies them silently.
- `benches/judgment.py` now exposes `Sim`, `TOOLS`, `BOOK`, `SYS`, `TURNS`, `score()` and runs the
  chat bench under `main()`; it also takes an optional bearer `KEY` from the environment. Same
  behaviour: original and refactored score the same model identically (checked on a live endpoint,
  twice).
