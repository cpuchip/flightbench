"""Time to first token on the production Qwen3.8-27B server (the shipped default on card 0), thinking on and off.

For each prompt size (about 100, 1k, 4k, 16k tokens of natural text plus a question) and each thinking mode, send the
same request three times in a row, streaming, and record per request:
  ttft   seconds from the request to the first streamed delta of any kind (reasoning or content)
  ttfc   seconds to the first CONTENT delta (with thinking on, this is after the whole reasoning block)
  prompt tokens as the server counts them (usage), completion tokens, decode tok/s over the stream
The first send of a size is cold for the prefix cache; the second and third are warm if the engine caches the prefix
(block size 448 on this model), so the pair also answers the long-prompt prefix-cache question. Usage:
  python ttft.py  (reads api_key.txt beside it; PORT env, default 18020; OUT env for the results file)
"""
import json
import os
import sys
import time
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
KEY = open(os.path.join(HERE, "api_key.txt"), encoding="utf-8").read().strip()
PORT = os.environ.get("PORT", "18020")
BASE = f"http://127.0.0.1:{PORT}"
OUT = os.environ.get("OUT", os.path.join(HERE, "ttft-results.jsonl"))
FILLER = os.environ.get("FILLER", r"<workspace>\projects\qwen38-pr43\docs\v0.28-validation.md")

text = open(FILLER, encoding="utf-8", errors="replace").read()
words = text.split()


def prompt_of(n_tokens):
    # about 0.75 words per token for English prose with numbers; the server's usage figure is what we report
    n_words = max(20, int(n_tokens * 0.72))
    body = " ".join(words[:n_words])
    return ("Here is an excerpt from an engineering record.\n\n" + body +
            "\n\nIn two sentences, what is the record measuring? Answer plainly.")


def model_name():
    req = urllib.request.Request(BASE + "/v1/models", headers={"Authorization": f"Bearer {KEY}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["data"][0]["id"]


def one(model, prompt, thinking, max_tokens):
    payload = {
        "model": model, "stream": True, "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": bool(thinking)},
    }
    req = urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(payload).encode(),
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    t0 = time.perf_counter()
    ttft = ttfc = None
    n_content = n_reason = 0
    usage = None
    last = t0
    with urllib.request.urlopen(req, timeout=600) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            obj = json.loads(data)
            if obj.get("usage"):
                usage = obj["usage"]
            for ch in obj.get("choices", []):
                d = ch.get("delta", {})
                now = time.perf_counter()
                if d.get("reasoning_content") or d.get("reasoning"):
                    n_reason += 1
                    if ttft is None: ttft = now - t0
                if d.get("content"):
                    n_content += 1
                    if ttft is None: ttft = now - t0
                    if ttfc is None: ttfc = now - t0
                last = now
    total = last - t0
    comp = usage.get("completion_tokens") if usage else None
    return {"ttft": ttft, "ttfc": ttfc, "total_s": total, "prompt_tokens": usage.get("prompt_tokens") if usage else None,
            "completion_tokens": comp, "decode_tok_s": (comp / (total - (ttft or 0))) if (comp and ttft is not None and total > ttft) else None,
            "reason_chunks": n_reason, "content_chunks": n_content}


def main():
    model = model_name()
    print("model", model, "server", BASE)
    sizes = [int(s) for s in os.environ.get("SIZES", "100,1000,4000,16000").split(",")]
    repeats = int(os.environ.get("REPEATS", "3"))
    with open(OUT, "a", encoding="utf-8") as f:
        for n in sizes:
            prompt = prompt_of(n)
            for thinking in (False, True):
                max_tokens = 64 if not thinking else 1200
                for i in range(repeats):
                    r = one(model, prompt, thinking, max_tokens)
                    r.update({"size": n, "thinking": thinking, "rep": i + 1, "utc": time.strftime("%H:%M:%SZ", time.gmtime())})
                    f.write(json.dumps(r) + "\n"); f.flush()
                    print(f"{r['utc']} size~{n:5d} prompt={r['prompt_tokens']} think={int(thinking)} rep={i+1} "
                          f"ttft={r['ttft']:.3f}s ttfc={(r['ttfc'] if r['ttfc'] is not None else float('nan')):.3f}s "
                          f"comp={r['completion_tokens']} decode={(r['decode_tok_s'] or 0):.0f} tok/s", flush=True)


if __name__ == "__main__":
    main()
