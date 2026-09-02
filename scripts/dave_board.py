"""Assemble the 2026-09-02 local-fleet table for the report: judgment (v4) and mission (v6.1 final) per
model and thinking mode, from the raw jsonl rows under results/raw/dave/ and the CLI rows.

  python scripts/dave_board.py
"""
import json, os, sys
from collections import defaultdict
sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "results", "raw", "dave")

def rows(path):
    p = os.path.join(D, path)
    return [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()] if os.path.exists(p) else []

STACK = {
    "qwen3.8-27b": ("vLLM 0.27.1 patched: W4A16 AutoRound weights, int4 per-token-head KV, DFlash2 speculation", "qwen3.8-27B"),
    "qwen-q4km-off": ("llama.cpp b10510: Q4_K_M weights, f16 KV", "qwen3.8-27B"),
    "qwen-q4km-on": ("llama.cpp b10510: Q4_K_M weights, f16 KV", "qwen3.8-27B"),
    "gemma-e4b": ("llama.cpp b10510: UD-Q4_K_XL", "gemma-4-E4B-it"),
    "gemma-12b": ("llama.cpp b10510: Q4_K_M", "gemma-4-12B-it"),
    "gemma-26b-a4b": ("llama.cpp b10510: UD-Q4_K_XL", "gemma-4-26B-A4B-it"),
    "gemma-31b": ("llama.cpp b10510: Q4_K_M", "gemma-4-31B-it"),
}
ORDER = ["qwen3.8-27b", "qwen-q4km-off", "qwen-q4km-on", "gemma-e4b", "gemma-12b", "gemma-26b-a4b", "gemma-31b"]

judg = defaultdict(list); miss = defaultdict(list)
# the clean local rows are the first v6.1 series (before 16:45Z); the "final" local files are contaminated
# by a stopped series that kept running (see results/raw/dave/README.md)
for r in rows("judgment-whale.jsonl") + rows("judgment-local-v61.jsonl") + rows("judgment-gaps.jsonl"):
    judg[(r["model"], r.get("think"))].append(r)
for r in rows("mission-whale-final.jsonl") + rows("mission-whale-final-think6k.jsonl") + rows("mission-local-v61.jsonl") + rows("mission-gaps.jsonl"):
    miss[(r["model"], r.get("think"))].append(r)

def fmt_j(rs): return ", ".join(f"{r['n_ok']}/8" for r in rs) if rs else "n/a"
def fmt_m(rs): return ", ".join(f"{r['n_ok']}/18" for r in rs) if rs else "n/a"
def misses(rs, n):
    out = []
    for r in rs:
        out.append("/".join(k.split("-", 1)[0] for k, v in r["decisions"].items() if not v) or "clean")
    return "; ".join(out)

print("| model | stack | thinking | judgment (8) | mission (18), per run | mission misses (decision codes per run) |")
print("|---|---|---|---|---|---|")
keys = sorted(set(list(judg) + list(miss)), key=lambda k: (ORDER.index(k[0]) if k[0] in ORDER else 99, str(k[1])))
for k in keys:
    stack, name = STACK.get(k[0], ("?", k[0]))
    think = {"on": "on", "off": "off", "none": "n/a"}.get(k[1], str(k[1]))
    print(f"| {name} | {stack} | {think} | {fmt_j(judg.get(k, []))} | {fmt_m(miss.get(k, []))} | {misses(miss.get(k, []), 18)} |")

# CLI rows (v6.1 only), latest per cell
cli = {}
p = os.path.join(ROOT, "results", "cli-runs", "rows.jsonl")
for r in (json.loads(l) for l in open(p, encoding="utf-8") if l.strip()):
    if r["bench"] == "mission" and r.get("version") == "6.1":
        cli[(r["cli"], r["model"])] = r
if cli:
    print("\n| harness | model | mission v6.1 (18) | misses |")
    print("|---|---|---|---|")
    for (c, m), r in sorted(cli.items()):
        print(f"| {c} | {m} | {r['n_ok']}/18 | {', '.join(k for k, v in r['decisions'].items() if not v) or 'clean'} |")
