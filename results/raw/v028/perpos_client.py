"""Cohort client with PER-POSITION acceptance and wall clock. Eight real prompts at 1024 output
tokens, four seeds, counters read per prompt. Emits per row: drafts, drafted tokens, accepted,
round, tok/step, wall seconds, output tokens, decode tok/s, distinct-word and gzip ratios, and
the accepted-per-position deltas so the acceptance curve by draft position can be built.
Registered use: arm 1 (draft width 3..7) and arm 2 (VLLM_DFLASH2_LOOKUP_CHEAP_CTX)."""
import re, hashlib, base64
import gzip, json, os, re, sys, time, urllib.request
sys.stdout.reconfigure(encoding="utf-8")
PORT = os.environ["PORT"]; KEY = os.environ["VLLM_API_KEY"]; ARM = os.environ.get("ARM", "?")
SEEDS = [int(s) for s in os.environ.get("SEEDS", "1,2,3,4").split(",")]
BASE = f"http://127.0.0.1:{PORT}"
NAMES = ("drafts", "draft_tokens", "accepted_tokens")
POS_RE = re.compile(r'^vllm:spec_decode_num_accepted_tokens_per_pos_total\{[^}]*position="(\d+)"[^}]*\}\s+([0-9.]+)', re.M)
prompts = []
for line in open("/app/bench/prompts_real.jsonl", encoding="utf-8"):
    line = line.strip()
    if not line: continue
    o = json.loads(line); p = o.get("prompt") or o.get("text") or next(iter(o.values()))
    if isinstance(p, str) and p.strip(): prompts.append(p)
    if len(prompts) == 8: break

def metrics():
    rq = urllib.request.Request(BASE + "/metrics", headers={"Authorization": "Bearer " + KEY})
    txt = urllib.request.urlopen(rq, timeout=60).read().decode()
    tot = {n: float(re.search(rf"^vllm:spec_decode_num_{n}_total\{{[^}}]*\}}\s+([0-9.]+)", txt, re.M).group(1)) for n in NAMES}
    pos = {int(p): float(v) for p, v in POS_RE.findall(txt)}
    return tot, pos

def stats(s):
    w = s.split(); raw = s.encode("utf-8")
    return (len(set(w)) / len(w) if w else 0.0), (len(gzip.compress(raw)) / len(raw) if raw else 0.0)

print(f"PERPOS arm={ARM} prompts={len(prompts)} seeds={SEEDS}", flush=True)
for seed in SEEDS:
    for pi, p in enumerate(prompts):
        try:
            b, bp = metrics()
        except Exception as e:
            print(f'SERVER_GONE arm={ARM} seed={seed} prompt={pi} err={str(e)[:80]}', flush=True); break
        payload = {"model": "qwen3.8-27b", "prompt": p, "max_tokens": 1024, "seed": seed}
        if os.environ.get("GREEDY") == "1": payload["temperature"] = 0  # greedy cell: the bonus token is the argmax
        body = json.dumps(payload).encode()
        rq = urllib.request.Request(BASE + "/v1/completions", data=body,
            headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY})
        t0 = time.perf_counter()
        try:
            d = json.load(urllib.request.urlopen(rq, timeout=1800))
        except urllib.error.URLError as e:
            if not isinstance(e, urllib.error.HTTPError):
                print(f'SERVER_GONE arm={ARM} seed={seed} prompt={pi} err={str(e)[:80]}', flush=True); break
            # 2026-09-05: a 500 mid-run ended ap11sa0 at 13 rows with the engine's error uncaptured. Print the server log's
            # error lines once, record the row as failed, and go on, so the cell keeps its other rows and the cause.
            print(f'ROW_ERROR arm={ARM} seed={seed} prompt={pi} http={e.code}', flush=True)
            if not globals().get('_dumped'):
                globals()['_dumped'] = True
                try:
                    lines = open('/tmp/server.log', errors='replace').read().splitlines()
                    err = [l for l in lines if re.search(r'Error|Traceback|assert|illegal|died|abort', l)]
                    print('SERVER_ERROR_BEGIN', flush=True); print(chr(10).join(l[:300] for l in (err[-40:] or lines[-40:])), flush=True); print('SERVER_ERROR_END', flush=True)
                except Exception as ee:
                    print('SERVER_ERROR_UNREADABLE', ee, flush=True)
            continue
        wall = time.perf_counter() - t0
        a, ap = metrics()
        dr = a["drafts"] - b["drafts"]; dt = a["draft_tokens"] - b["draft_tokens"]; ac = a["accepted_tokens"] - b["accepted_tokens"]
        out = d["usage"]["completion_tokens"]
        dist, comp = stats(d["choices"][0].get("text", "") or "")
        perpos = {k: ap.get(k, 0.0) - bp.get(k, 0.0) for k in sorted(set(ap) | set(bp))}
        if dr <= 0:
            print(f"ROW arm={ARM} seed={seed} prompt={pi} NO_SPEC_ACTIVITY out={out} wall={wall:.1f}", flush=True); continue
        pp = " ".join(f"p{k}={v:.0f}" for k, v in perpos.items())
        print(f"ROW arm={ARM} seed={seed} prompt={pi} drafts={dr:.0f} dtok={dt:.0f} acc={ac:.0f} round={dt/dr:.3f} "
              f"tok_per_step={1+ac/dr:.3f} out={out} wall={wall:.1f} tok_s={out/wall:.1f} "
              f"distinct={dist:.3f} gzip={comp:.3f} {pp}", flush=True)
        if os.environ.get("GREEDY") == "1":  # greedy cells: the completion text itself, for cross-box first-divergence comparison
            txt = d["choices"][0].get("text", "") or ""
            print(f"TEXT arm={ARM} seed={seed} prompt={pi} sha={hashlib.sha256(txt.encode()).hexdigest()[:16]} b64={base64.b64encode(txt.encode()).decode()}", flush=True)
