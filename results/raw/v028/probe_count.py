"""The maintainer's exact-output probe: greedy "count 1 to 30" must come back as the sequence, character-exact
after whitespace normalisation. Prints PASS/FAIL, the usage, and the head of the reply. BASE/KEY env."""
import json, os, re, sys, urllib.request
sys.stdout.reconfigure(encoding="utf-8")
base, key = os.environ["BASE"], os.environ["KEY"]
body = json.dumps({"model": "qwen3.8-27b", "messages": [{"role": "user", "content": "Count from 1 to 30 as a comma-separated list on one line, nothing else."}],
                   "max_tokens": 200, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}).encode()
req = urllib.request.Request(base + "/chat/completions", data=body, headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=300) as r:
    j = json.loads(r.read())
text = j["choices"][0]["message"]["content"] or ""
nums = [int(x) for x in re.findall(r"\d+", text)]
ok = nums == list(range(1, 31))
print(("PASS" if ok else "FAIL") + f" | completion_tokens={j.get('usage',{}).get('completion_tokens')} | {text.strip()[:80]!r}")
