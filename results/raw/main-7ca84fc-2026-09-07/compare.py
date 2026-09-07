"""Compare the main-branch cohort arms against the record's shipped-default soak passes (same
client, same eight prompts, 1024 tokens, four seeds per arm) and the TTFT ladder against the record's
2026-09-07 table. Row-level tok/step and tok/s; drafts-weighted acceptance; per-prompt means; and the
difference against the record's noise floor (sd 0.074 per 32-row arm; effects under 0.3 need two seed sets)."""
import json, re, statistics, sys, os
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
SOAK = r"<workspace>\projects\flightbench\results\raw\v028\soak-default.txt"

def rows(path, keep=lambda a: True):
    out = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.search(r"ROW arm=(\S+) seed=(\d+) prompt=(\d+) drafts=(\d+) dtok=(\d+) acc=(\d+) round=([0-9.]+) tok_per_step=([0-9.]+) out=(\d+) wall=([0-9.]+) tok_s=([0-9.]+)", line)
        if m and keep(m.group(1)):
            out.append(dict(arm=m.group(1), seed=int(m.group(2)), prompt=int(m.group(3)), drafts=int(m.group(4)),
                            acc=int(m.group(6)), tps=float(m.group(8)), out=int(m.group(9)), wall=float(m.group(10)), toks=float(m.group(11))))
    return out

def summarize(name, rs):
    if not rs:
        print(f"{name:26} no rows"); return None
    tps = [r["tps"] for r in rs]; toks = [r["toks"] for r in rs]
    D = sum(r["drafts"] for r in rs); A = sum(r["acc"] for r in rs)
    byp = {}
    for r in rs: byp.setdefault(r["prompt"], []).append(r["tps"])
    print(f"{name:26} rows={len(rs):3}  tok/step {statistics.mean(tps):.3f} (sd {statistics.pstdev(tps):.3f})  weighted {1+A/D:.3f}  tok/s {statistics.mean(toks):.1f}  out {statistics.mean(r['out'] for r in rs):.0f}")
    print("    per-prompt:", " ".join(f"{k}:{statistics.mean(v):.2f}" for k, v in sorted(byp.items())))
    return statistics.mean(tps), 1 + A / D, statistics.mean(toks), tps

print("=== MAIN 7ca84fc, fresh cache, shipped default, fermion card 1 ===")
m1 = summarize("main-a1 seeds 1-4", rows(os.path.join(HERE, "cohort-main-a1.txt")))
m2 = summarize("main-a2 seeds 5-8", rows(os.path.join(HERE, "cohort-main-a2.txt")))
print("=== RECORD pr43-6869c80, soak passes (seeds 1-4 each) ===")
rec = []
for p in ["soak-p1", "soak-p2", "soak-p3", "soak-p4", "soak-p5"]:
    s = summarize(p, rows(SOAK, lambda a, p=p: a == p))
    if s: rec.append(s)
if m1 and rec:
    mains = [m for m in (m1, m2) if m]
    mm = statistics.mean(m[0] for m in mains); rm = statistics.mean(r[0] for r in rec)
    mw = statistics.mean(m[1] for m in mains); rw = statistics.mean(r[1] for r in rec)
    mt = statistics.mean(m[2] for m in mains); rt = statistics.mean(r[2] for r in rec)
    print(f"\nDELTA main - record: tok/step row-mean {mm - rm:+.3f}  weighted {mw - rw:+.3f}  tok/s {mt - rt:+.1f}   (record arm-to-arm sd of row-mean: {statistics.pstdev([r[0] for r in rec]):.3f}; noise floor sd 0.074 per 32-row arm)")
    # paired by (seed, prompt) where both exist: main seeds 1-4 vs soak-p1 seeds 1-4
    a = {(r['seed'], r['prompt']): r['tps'] for r in rows(os.path.join(HERE, "cohort-main-a1.txt"))}
    b = {(r['seed'], r['prompt']): r['tps'] for r in rows(SOAK, lambda x: x == "soak-p1")}
    pairs = [(a[k], b[k]) for k in a if k in b]
    if pairs:
        d = [x - y for x, y in pairs]
        se = statistics.pstdev(d) / (len(d) ** 0.5) if len(d) > 1 else float('nan')
        print(f"PAIRED (seed,prompt) main-a1 vs soak-p1: n={len(d)} mean diff {statistics.mean(d):+.3f} tok/step, SE {se:.3f}, t {statistics.mean(d)/se if se else float('nan'):.2f}")

print("\n=== TTFT ladder, main (18021) ===")
p = os.path.join(HERE, "ttft-results.jsonl")
if os.path.exists(p):
    for l in open(p, encoding="utf-8"):
        d = json.loads(l)
        keep = {k: (round(v, 3) if isinstance(v, float) else v) for k, v in d.items() if k not in ("text", "prompt", "reasoning")}
        print(" ", keep)
else:
    print("  no ttft-results.jsonl")
