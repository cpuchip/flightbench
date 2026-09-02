"""Side-load that evicts a conversation's cached blocks between its turns: every few seconds, one
prefill-only request whose prompt is most of the KV pool, so the LRU prefix cache pushes the
conversation's oldest blocks out to the offload connector and the next turn must load them back.
  BASE, KEY env; argv: words-per-prompt, seconds between requests, stop-file path."""
import os, random, sys, time, json, urllib.request
sys.stdout.reconfigure(encoding="utf-8")
words, gap, stop = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
base, key = os.environ["BASE"], os.environ["KEY"]
# common English words tokenize at ~1 token each on this model (measured: 21,000 words -> 21,000 prompt
# tokens); random letter strings cost ~3.4 tokens a word and overran max_model_len (HTTP 400).
vocab = ("the of and to in is that for it as with on be by this from at or an are not have was but they "
         "which one you were all their more will when who about out up said than into some could them see "
         "other then now only its over also new after two how our work first well way even want because "
         "these give day most us time year people just know take good back think come".split())
n = 0
while not os.path.exists(stop):
    random.seed(n)
    prompt = " ".join(random.choice(vocab) for _ in range(words))
    body = json.dumps({"model": "qwen3.8-27b", "prompt": prompt, "max_tokens": 1, "temperature": 0}).encode()
    req = urllib.request.Request(base + "/completions", data=body, headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            u = json.loads(r.read()).get("usage", {})
        n += 1
        if n % 5 == 1: print(f"[churn] #{n} prompt_tokens={u.get('prompt_tokens')} {round(time.time()-t0,1)}s", flush=True)
    except Exception as e:
        print(f"[churn] error {repr(e)[:100]}", flush=True); time.sleep(5)
    time.sleep(gap)
print(f"[churn] stopped after {n} requests", flush=True)
