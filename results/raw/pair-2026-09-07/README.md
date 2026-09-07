# NVIDIA PAIR fronting llama-chip and vLLM, zero code (2026-09-07)

Question: can NVIDIA's Personal AI Router (PAIR) route to our own servers, vLLM behind
llama-chip, without forking it? Answer: yes, on this build, with a per-user engine
manifest override and no code change. The path proven here is

    client -> PAIR lmstudio-proxy (port 1234, IPv6 only, see finding 1)
           -> llama-chip external slot (127.0.0.1:8095, adds the bearer)
           -> vLLM qwen-prod (127.0.0.1:18020, Qwen3.8-27B W4A16 + DFlash2)

PAIR: github.com/NVIDIA/Personal-AI-Router at commit 13b6811 (2026-08-28), product
version 0.91.7 in services/versions.json; the thirteen Go workers built from source on
Windows with `go build` (the repo's build.bat wants jq, absent here). Node ran headless:
nvpair-ui-broker spawned over stdio JSON-RPC by pair-drive.py (a throwaway driver that
speaks the TUI's wire), which polls engine:status, lmstudio-proxy:get-status,
engine:models and discovery:get-nodes every 5 s. Michael's real LM Studio desktop was
running and holding 0.0.0.0:1234 the whole time and was not touched (80 models before
and after; no lms command ever ran).

## The override (override-lmstudio.json)

PAIR's engine-manager deep-merges a per-user manifest at
`%LOCALAPPDATA%\Nvidia Corporation\Personal AI Router\engines\<engine>.json` onto the
bundled one, and identifies a running engine by an HTTP probe, not by process name. So
the LM Studio engine was redirected wholesale:

1. `runtime.port` 8095: the llama-chip rig with the external slot for qwen-prod.
2. `runtime.ready`: GET `/nvpair-identify` expecting **404**. LM Studio answers 200 to
   every path it does not know (`{"error":"Unexpected endpoint or method"}`), so no
   200-probe can tell it from llama-chip; llama-chip's Go mux returns 404 for an unknown
   path. This is the identity discriminator, and it is a hack.
3. `runtime.start` neutralized (`cmd /c exit 0`) and `runtime.stop` nulled, so PAIR can
   never run `lms server start` or `lms server stop` against the real LM Studio while
   it believes llama-chip is LM Studio.
4. `actions.list_models` and `loaded_models` read OpenAI `/v1/models` (`data[].id`,
   loaded = every row with `object == "model"`) instead of LM Studio's `/api/v1/models`.
5. settings.json `force_ports: false`, so the broker does not try to move the engine
   onto a managed backend port at startup.

## Results

| step | result |
|---|---|
| node up (app:ready to first poll) | under 1 s; engine adopted `running:true healthy:true port:8095`, inventory `qwen3.8-27b`, node advertises it |
| GET /v1/models through PAIR | llama-chip's list (one model, owned_by llama-chip) |
| GET /v1/models on 127.0.0.1:1234 at the same moment | the real LM Studio, 80 models (finding 1) |
| chat, non-stream, 25 prompt tokens, 50 completion tokens, thinking off | http 200, 0.695 s total, TTFB 0.694 s |
| chat, stream, same prompt | first token 0.064 s, 0.403 s total, 16 chunks, 147.5 tok/s decode (completion tokens over total minus first token) |
| unknown model name through PAIR | 502 `{"error":"no available node advertises the requested model"}` (PAIR is in the path and routes by advertised inventory) |
| same request straight to vLLM :18020 with no key | 401 (llama-chip's bearer is what makes the hop work) |

Falsification (kill the rig, watch PAIR go red, restore, watch it go green), shell clock UTC:

| time | event |
|---|---|
| 04:08:11 | llama-chip rig killed |
| 04:08:15 | PAIR: engine `running:false healthy:false`, models empty, node advert dropped, warning "Upstream node fermion is no longer reachable"; chat through PAIR 502 |
| 04:08:40 | rig back (its own log, local 23:08:40); the 04:08:40.284 poll already shows adopted and healthy again |
| 04:08:45 | node re-advertises the model, the warning clears; stream chat 200, first token 0.303 s, 0.643 s total, 147.1 tok/s |
| 04:11:35 | shutdown RPC; broker exit 0; no worker left; override file and settings byte-identical; LM Studio still 80 models |

## Findings

1. **Port 1234 was bound twice.** With managed ports off, lmstudio-proxy bound `[::]:1234`
   (IPv6) while LM Studio held `0.0.0.0:1234` (IPv4); Windows lets both coexist. So
   `127.0.0.1:1234` reaches LM Studio and `[::1]:1234` reaches PAIR on the same box. On
   Linux the second bind would fail. Its port-availability check does not see this;
   worth an upstream issue.
2. **Identity is an HTTP probe with an expected status, nothing else.** That is what
   makes the masquerade possible and is also why the 404 trick is needed on a box where
   the real engine is also up.
3. **Recovery is fast:** engine down noticed within 4 s of the kill, re-adopted within
   5 s of the rig returning, re-advertised 5 s later.
4. The proxy passes SSE through untouched (vLLM's multi-token chunks under speculative
   decoding arrive as 16 chunks for 50 tokens) and returns its own 502 for models no node
   advertises.

## What a real fork would change

Everything above is a prototype instrument; the override lies to PAIR about what it is
talking to. The honest change is a first-class **OpenAI-compatible server** engine kind:
a manifest with no install and no CLI, identity from `/v1/models`, inventory from
`data[].id`, and the broker, lmstudio-proxy, node-info and the desktop's EngineTypes
contract accepting that kind beside ollama and lmstudio. Estimated as a few hundred
lines across those services; the manifest system and the proxy already carry the rest.

## Files

- `override-lmstudio.json`, `settings.json`: what was written into PAIR's app dir.
- `llama-chip-external.json`: the llama-chip rig config (external slot, key from env).
- `pair-drive.py`: the stdio JSON-RPC driver.
- `driver.log`: every poll and notification (node uuid, fingerprint and mesh IP redacted).
- `broker.stderr.log`: the broker and its workers' logs (same redaction).
- `chat-req.json`, `chat1.json`: the non-stream request and response through PAIR.
- `stream2.log`: the streaming run after recovery.
- `falsify.log`: the red/green transcript.
