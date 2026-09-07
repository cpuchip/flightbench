# llama-chip fleet: GPU and box management, first class (2026-09-07 night)

Michael ruled: skip PAIR, borrow its best, make llama-chip the first-class citizen; build and test
with threadchip tonight. Marks: warm standby default off (on per profile); model sharing
peer-to-peer over the mesh, never through the hub. Spec:
private-workspace/.spec/proposals/llama-chip-fleet.md. Repo: cpuchip/llama-chip, integration branch
`fleet-tonight` (`fleet` collides with `fleet/core` in git's ref namespace). Fleet tonight: fermion
(this box, two RTX 4090s) + threadchip (RTX 3090). nocix is offline (its seat's Anthropic auth
expired ~2 weeks ago; not re-authed).

Two seats: fermion (workspace-basecamp) owned rig/gpu/router/fed/telemetry/yield on fleet/core;
threadchip owned internal/share and docs on fleet/share. Coordinates (mesh IPs, GPU UUIDs) are
redacted in every file here.

## Phase 1: the slot contract, measured (fermion, real path)

Every node publishes per-GPU and per-slot state that a peer or scheduler can place work on, all
measured, none configured. Package internal/telemetry; per-process VRAM by platform
(internal/gpu/procs*.go: Windows GPU perf counters via typeperf since nvidia-smi cannot attribute
per process there, Linux nvidia-smi compute-apps); router observes every proxied request for
tok/s, TTFT and cache-hit rate; peers carry it in /api/fed/local.

Proven on fermion: the 35B GGUF on card 1 and the vLLM production server as an external slot on
card 0.

| card | slot | used MiB | ours MiB | foreign MiB | attribution |
|---|---|---|---|---|---|
| 0 | qwen3.8-27b (external, vLLM) | 23664 | 23664 | 0 | external baseline captured at first healthy |
| 1 | qwen3.6-35b-a3b (llama-server) | 20910 | 20910 | 0 | by our llama-server PID |

The 35B slot's first request through fermion's router: PID 87804, VRAM estimate 22246 MiB (against
20910 actual), TTFT 481 ms, 174 tok/s, cache-hit 0 on a cold prompt, inflight/queued tracked live.
`fermion-status-phase1.json` is the captured `/api/status` (coordinates redacted). Card 0 first
sampled 0 ours before the external baseline landed, then corrected to 23664 on the next 5 s sample:
a one-sample warm-up, not a bug (the baseline is taken when the upstream first answers healthy).

## Phase 2: yield to the foreground (fermion; two-box real path pending threadchip swap)

Package internal/yield. When a foreign process takes VRAM on a card past a threshold for the hold
delay, the controller drains and unloads the rig's llama-server slots there so requests fail over
to a fleet peer, and reloads them when the foreign use has been gone for the restore delay.
External slots are never unloaded (the rig did not launch a vLLM container and cannot move it); the
card is still marked yielding so placement avoids it. Manual override at `POST /api/yield
{"gpu":N,"on":true|false}`, which ignores the threshold and hold (a human clicking game-mode wants
the card now). Warm standby is off by default: on yield the controller best-effort asks online
peers to ensure the model, but does not hold it warm in advance unless a profile says so.

Unit-tested (internal/yield/yield_test.go): yield after the hold, restore after the delay, no
restore while the game still runs, disabled policy never yields, manual ignores threshold/hold,
external slot never unloaded. The two-box real-path test (hog card 1 on fermion, watch the work
land on threadchip, release, watch it come back) runs once threadchip is on `fleet-tonight`.

## Phase 4: peer-to-peer model sharing (threadchip's lane)

Package internal/share (fleet/share, threadchip): a node serves its own GGUFs by content hash
(`/api/models/blob?sha256=`, HTTP ranges so a fetch resumes and is sha256-verified on completion),
and `llama-chip fetch <model> --from <peer>` pulls them; `/api/models` gains sha256 and size. Never
through the hub (Michael's mark). docs/onboarding.md carries the bring-up, the credentials-by-env
rule, the context-must-agree-across-nodes rule, and the examples rule. Unit-tested; the real-path
fetch across boxes runs after the swap.

## Discipline notes from tonight

- Three coordinate-class leaks were caught before they shipped: a mesh IP in fetch.go help text
  (threadchip, scanning its own diff), and two mesh IPs in the PAIR prototype logs earlier.
  Standing rule now in the fleet docs: a mesh IP or RFC1918 address in an example is the same class
  of leak as a token in a config; the wall-check greps for neither, so a human scans examples.
- threadchip held every push (a public-repo publish is Michael's pen, not a relay's) and handed
  fermion a verified git bundle over a mesh-only, read-only, two-file HTTP server it killed after
  the hand-off. Nothing published from that box.
- Credentials by env var: config gained `token_env` and `hub_token_env` so a node config carries a
  variable name, not a secret, since a config is the first thing pasted into a chat when debugging.

## Files

- `README.md` (this).
- `fermion-status-phase1.json` — fermion `/api/status`, coordinates redacted: the measured slot
  contract for both cards and the peer roster.
