"""The runtime comparison for the results page: one model (Qwen3.8-27B), every runtime and KV-cache
configuration it was served with today, thinking off and on, judgment (v4) and mission (v6.1).

  python scripts/runtime_board.py            # markdown table on stdout
"""
import json, os, sys
from collections import defaultdict
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "results", "raw", "dave")

def rows(path):
    p = os.path.join(D, path)
    return [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()] if os.path.exists(p) else []

# model alias -> (runtime, weights, KV cache, speculation)
CONFIG = {
    "qwen3.8-27b":          ("vLLM 0.27.1 patched", "W4A16 AutoRound", "int4 per-token-head (Triton)", "DFlash2, 7 drafts"),
    "qwen3.8-27b-kv-fast":  ("vLLM 0.27.1 patched", "W4A16 AutoRound", "bf16 (FlashAttention)", "DFlash2, 7 drafts"),
    "qwen3.8-27b-kv-long":  ("vLLM 0.27.1 patched", "W4A16 AutoRound", "int8 per-token-head (Triton)", "DFlash2, 7 drafts"),
    "qwen3.8-27b-kv-huge":  ("vLLM 0.27.1 patched", "W4A16 AutoRound", "KVarN k4v2 g128 (4-bit K, 2-bit V)", "DFlash2, 7 drafts"),
    "qwen-q4km-off":        ("llama.cpp b10510", "Q4_K_M GGUF", "f16", "none"),
    "qwen-q4km-on":         ("llama.cpp b10510", "Q4_K_M GGUF", "f16", "none"),
}
ORDER = ["qwen3.8-27b-kv-fast", "qwen3.8-27b-kv-long", "qwen3.8-27b", "qwen3.8-27b-kv-huge", "qwen-q4km-off", "qwen-q4km-on"]

judg = defaultdict(list); miss = defaultdict(list)
for r in rows("judgment-whale.jsonl") + rows("judgment-vllm-kv.jsonl") + rows("judgment-gaps.jsonl"):
    if r["model"] in CONFIG: judg[(r["model"], r.get("think"))].append(r)
# the whale's mission rows: thinking off at the 900 cap (final), thinking on at the 6,000 cap (like the tiers)
for r in rows("mission-whale-final.jsonl"):
    if r.get("think") == "off": miss[(r["model"], "off")].append(r)
for r in rows("mission-whale-final-think6k.jsonl"):
    miss[(r["model"], "on")].append(r)
for r in rows("mission-vllm-kv.jsonl") + rows("mission-gaps.jsonl"):
    if r["model"] in CONFIG: miss[(r["model"], r.get("think"))].append(r)

def j(rs): return ", ".join(f"{r['n_ok']}/8" for r in rs) if rs else "n/a"
def m(rs): return ", ".join(f"{r['n_ok']}/18" for r in rs) if rs else "n/a"
def mm(rs): return "; ".join("/".join(k.split("-", 1)[0] for k, v in r["decisions"].items() if not v) or "clean" for r in rs)

print("| runtime | weights | KV cache | speculation | thinking | judgment (8) | mission (18), per run | mission misses |")
print("|---|---|---|---|---|---|---|---|")
keys = sorted(set(list(judg) + list(miss)), key=lambda k: (ORDER.index(k[0]) if k[0] in ORDER else 99, str(k[1])))
for k in keys:
    rt, w, kv, sp = CONFIG[k[0]]
    print(f"| {rt} | {w} | {kv} | {sp} | {k[1]} | {j(judg.get(k, []))} | {m(miss.get(k, []))} | {mm(miss.get(k, []))} |")
