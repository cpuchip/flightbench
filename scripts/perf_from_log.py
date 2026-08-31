import sys, re, statistics as st
sys.stdout.reconfigure(encoding='utf-8')
"""Harvest per-request performance from a llama-server log: mean prefill and
decode tok/s, request count, and warm-turn prompt reuse (how few prompt
tokens were reprocessed on continuation turns... the cache doing its job).
Usage: python scripts/perf_from_log.py <server.log> <alias>"""
path, alias = sys.argv[1], sys.argv[2]
txt = open(path, encoding='utf-8', errors='replace').read()
pp = [float(x) for x in re.findall(r'prompt eval time =.*?\(\s*([\d.]+) ms per token', txt)]
dd = [float(x) for x in re.findall(r'eval time =\s*[\d.]+ ms /\s*\d+ tokens \(\s*([\d.]+) ms per token', txt)]
ptoks = [int(x) for x in re.findall(r'prompt eval time =\s*[\d.]+ ms /\s*(\d+) tokens', txt)]
n = len(ptoks)
prefill = round(1000 / st.mean(pp)) if pp else 0
decode = round(1000 / st.mean(dd), 1) if dd else 0
warm = [t for t in ptoks[1:] if t < (ptoks[0] if ptoks else 1)]
reuse = f"median warm-turn prompt reprocess {int(st.median(warm))} tok" if warm else "n/a"
print(f"[perf] {alias}: {n} requests · prefill ~{prefill} tok/s · decode ~{decode} tok/s · {reuse}")
