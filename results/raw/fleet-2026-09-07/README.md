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

## Two-box tests, PASSED (2026-09-07, driven from fermion; threadchip on fleet-tonight)

Both boxes on fleet-tonight; the same alias `qwen3.6-35b-a3b` served on fermion (card 1, ctx
32768) and threadchip (card 0, ctx 32768). fermion reads threadchip's full slot contract over the
mesh (loaded, queue depth, one GPU), so cross-box slot-contract propagation works. Discriminator:
threadchip's own per-slot request counter (fermion could read it because fermion-to-threadchip is
outbound; the reverse is firewalled, see below).

| step | expected | observed |
|---|---|---|
| baseline request through fermion | served local | reply OK, threadchip counter flat at 0 |
| manual yield card 1, then request | fail over to threadchip | 35B unloaded, card 1 yielding, threadchip counter 0 to 1 to 2 |
| release yield | fermion reloads, takes work back | restored ~39s (30s cold-timer + reload), card 1 un-yielded |
| fresh session after restore | served local | threadchip counter flat |
| the session that had failed over | stays on threadchip (its cache is there) | threadchip counter rose: prefix affinity holding a conversation to the node with its cache |
| automatic yield: a 2 GB model launched as a foreign process on card 1 (pid, 2616 MiB) | detect, hold, yield, fail over | foreign>1024 held 5s, card 1 yielded, 35B unloaded, request failed over (counter 4 to 5) |
| kill the hog (game exits) | fermion restores | 35B reloaded on card 1 in ~18s, card 1 un-yielded |

This is the whole "start a game, the fleet shifts models and requests to another box, close the
game, it comes back" cycle Michael named as the thing making it hard to work, proven on the real
path across two machines. Affinity is the answer to the round-robin cache-miss concern: a
continued conversation sticks to the node holding its prefix cache instead of alternating.

Two defects the tests surfaced, both fixed:
- A startup race: a card carrying a not-yet-baselined external slot (the vLLM container on card 0)
  briefly read fully-foreign and self-yielded for ~20s. compute() now treats such a card as
  unknown (foreign 0) until the baseline lands. Unit-tested.
- Model sharing shipped wired-off (threadchip's catch): the merge took the WithShare method but
  main never called OpenIndex/WithShare, so the blob endpoint answered 404 and every model
  advertised sha256=(none) on a live node. Wired via threadchip's fleet/share-wiring commits.

Firewall note: fermion's inbound 8090 is filtered (the existing allow rule is program-scoped to a
different binary path), so threadchip-originated requests cannot yet route to fermion. Opening it
needs an elevated rule this seat could not create; the tests drive from fermion, which is outbound,
so they were unaffected. Carry-forward for Michael: a scoped inbound allow (TCP 8090 from
threadchip's mesh IP) for the full bidirectional pool.
