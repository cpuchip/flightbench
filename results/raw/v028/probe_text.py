"""Greedy text probes for character-exact comparison across cells: several prompts, thinking off, temperature 0.
Writes one JSON line per prompt {prompt_id, text, completion_tokens} to the file in argv[1]. BASE/KEY env."""
import json, os, sys, urllib.request
sys.stdout.reconfigure(encoding="utf-8")
base, key, out = os.environ["BASE"], os.environ["KEY"], sys.argv[1]
PROMPTS = {
  "count30": "Count from 1 to 30 as a comma-separated list on one line, nothing else.",
  "clone": "Write the exact shell commands to clone the GitHub repository syv-ai/qwen38-27b-rtx3090 and list its top-level files. Commands only.",
  "essay": "In about 150 words, explain how a paged KV cache lets an inference server serve long prompts. Plain prose.",
  "json": "Return a JSON object with keys name, population, capital for the three most populous countries. JSON only.",
}
with open(out, "w", encoding="utf-8") as f:
    for pid, p in PROMPTS.items():
        body = json.dumps({"model": "qwen3.8-27b", "messages": [{"role": "user", "content": p}], "max_tokens": 300, "temperature": 0,
                           "chat_template_kwargs": {"enable_thinking": False}}).encode()
        req = urllib.request.Request(base + "/chat/completions", data=body, headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r: j = json.loads(r.read())
        text = j["choices"][0]["message"]["content"] or ""
        f.write(json.dumps({"prompt_id": pid, "text": text, "completion_tokens": j.get("usage", {}).get("completion_tokens")}) + "\n")
        print(f"  {pid}: {j.get('usage', {}).get('completion_tokens')} tok | {text.strip()[:70]!r}")
