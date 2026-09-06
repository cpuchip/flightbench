"""Overnight soak at the shipped defaults: read soak-default.docker.txt (the container's stdout kept by the keeper) and
report per pass: rows, steady ms/step (boundary rows and the two warm-up rows of pass 1 excluded), tokens per step, errors;
the drift first-to-last pass; and row-level determinism across passes (rounds and accepted tokens per (prompt, seed) must
match pass 1 if one boot stays on one trajectory). Usage: soak_summary.py [file]"""
import sys, os, re, statistics as st, collections
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
f = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "soak-default.docker.txt")
passes = collections.OrderedDict(); cur = None; errors = []; meta = []
for line in open(f, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    m = re.match(r"PASS (\d+) START (\S+)", line)
    if m: cur = int(m.group(1)); passes[cur] = {"start": m.group(2), "rows": [], "end": None, "rc": None}; continue
    m = re.match(r"PASS (\d+) END (\S+) rc=(\d+)", line)
    if m and int(m.group(1)) in passes: passes[int(m.group(1))].update(end=m.group(2), rc=int(m.group(3))); continue
    if line.startswith("ROW ") and cur is not None and "NO_SPEC" not in line:
        d = dict(re.findall(r"(\w+)=([0-9.]+)", line)); passes[cur]["rows"].append({k: float(v) for k, v in d.items()}); continue
    if re.search(r"ROW_ERROR|SERVER_GONE|SERVER_ERROR|ENGINE GONE|NO HEALTH|illegal", line): errors.append(line[:200])
    if re.match(r"SOAK|RESOLVED|SEQUENCE|Graph capturing", line): meta.append(line[:160])
for m in meta: print(m)
key = lambda x: (x["prompt"], x["seed"]); tps = lambda x: x["acc"] / x["drafts"] + 1
base = {key(r): (r["round"], r["acc"], r["drafts"]) for r in passes[min(passes)]["rows"]} if passes else {}
print(f"\npass  rows  steady ms/step (min-max)   tok/step   rows identical to pass 1 (round,acc,drafts)   start-end  rc")
first = last = None
for p, d in passes.items():
    rows = d["rows"]
    if not rows: print(f"{p:4d}     0  (no rows yet)"); continue
    steady = [r for r in rows if r["out"] >= 16 and not (p == 1 and r["seed"] == 1 and r["prompt"] in (0, 1))]
    ms = [1000 * r["wall"] / r["drafts"] for r in steady]
    ident = sum(1 for r in rows if base.get(key(r)) == (r["round"], r["acc"], r["drafts"]))
    if ms:
        s = st.mean(ms); first = first or s; last = s
        print(f"{p:4d}  {len(rows):4d}  {s:6.1f} ({min(ms):5.1f}-{max(ms):5.1f})   {st.mean(tps(r) for r in rows):6.3f}   {ident:2d} of {len(rows)}   {d['start']}-{d['end'] or '...'}  {d['rc'] if d['rc'] is not None else ''}")
if first and last: print(f"\ndrift, steady ms/step first pass {first:.1f} to last complete pass {last:.1f}")
print(f"errors: {len(errors)}"); [print("  " + e) for e in errors[:10]]
