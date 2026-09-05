"""Block-verification cells, read with THE BOOT AS THE UNIT. Four boots: std1, blk1, blk2, std2.
Each boot is reduced to one pooled aggregate (tokens per step = 1 + A/R over all its rows, decode
tok/s = output tokens / wall over all rows, round = N/R). The two counterbalanced boot pairs
(std1,blk1) and (std2,blk2) give two paired differences: descriptive at n=2, reported with the
direction and the spread, never a t. Per-position acceptance per 1000 rounds beside each boot,
and the within-boot paired-row view as a secondary, clearly labelled as within-boot only."""
import os, re, statistics as st, sys
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))

def load(name):
    p = os.path.join(HERE, f"block-{name}.txt")
    rows, resolved = {}, ""
    if not os.path.exists(p): return rows, resolved
    for line in open(p, encoding="utf-8", errors="replace"):
        if line.startswith("RESOLVED"): resolved = line.strip()
        if not line.startswith("ROW "): continue
        d = dict(re.findall(r"(\w+)=([0-9.]+)", line))
        if "drafts" not in d: continue
        rows[(int(float(d["seed"])), int(float(d["prompt"])))] = {a: float(b) for a, b in d.items()}
    return rows, resolved

def agg(rows):
    R = sum(r["drafts"] for r in rows.values()); A = sum(r["acc"] for r in rows.values()); N = sum(r["dtok"] for r in rows.values())
    out = sum(r["out"] for r in rows.values()); wall = sum(r["wall"] for r in rows.values())
    pos = {}
    for r in rows.values():
        for k, v in r.items():
            if k.startswith("p") and k[1:].isdigit(): pos[int(k[1:])] = pos.get(int(k[1:]), 0) + v
    return {"tps": 1 + A / R, "tok_s": out / wall, "round": N / R, "rows": len(rows), "R": R,
            "pos": {k: 1000 * v / R for k, v in sorted(pos.items())}}

boots = {}
for n in ("std1", "blk1", "blk2", "std2"):
    rows, res = load(n)
    if len(rows) >= 8: boots[n] = (agg(rows), res, rows)
print(f"boots in: {list(boots)}")
for n, (a, res, _) in boots.items():
    print(f"  {n:<5} rows={a['rows']:2d} rounds={a['R']:5.0f} tok/step={a['tps']:.3f} tok/s={a['tok_s']:6.1f} round={a['round']:.3f} | {res[:110]}")
pairs = [("std1", "blk1"), ("std2", "blk2")]
diffs_t, diffs_s = [], []
for s, b in pairs:
    if s in boots and b in boots:
        dt = boots[b][0]["tps"] - boots[s][0]["tps"]; ds = boots[b][0]["tok_s"] - boots[s][0]["tok_s"]
        diffs_t.append(dt); diffs_s.append(ds)
        print(f"pair ({s},{b}): d tok/step {dt:+.3f}   d tok/s {ds:+.1f}   d round {boots[b][0]['round']-boots[s][0]['round']:+.3f}")
if len(diffs_t) == 2:
    print(f"BOOT-LEVEL (n=2 pairs, descriptive): d tok/step {st.mean(diffs_t):+.3f} (both {'positive' if all(d>0 for d in diffs_t) else 'negative' if all(d<0 for d in diffs_t) else 'mixed'}), "
          f"d tok/s {st.mean(diffs_s):+.1f} ({'both positive' if all(d>0 for d in diffs_s) else 'both negative' if all(d<0 for d in diffs_s) else 'mixed'})")
print("per-position accepted per 1000 rounds:")
for n, (a, _, _) in boots.items():
    print(f"  {n:<5} " + " ".join(f"p{k}={v:.0f}" for k, v in a["pos"].items() if v > 0.5))
# secondary: within-boot paired rows across the two boots of each pair (rows are NOT independent of boot)
for s, b in pairs:
    if s in boots and b in boots:
        rs, rb = boots[s][2], boots[b][2]; keys = sorted(set(rs) & set(rb))
        d = [(1 + rb[k]["acc"] / rb[k]["drafts"]) - (1 + rs[k]["acc"] / rs[k]["drafts"]) for k in keys]
        print(f"within-pair rows ({s},{b}), n={len(d)}: mean {st.mean(d):+.3f} sd {st.stdev(d):.3f} positive {sum(1 for x in d if x>0)}/{len(d)}  [rows share a boot: not independent replicates]")
print("registered: tok/step up at unchanged round with no wall-clock penalty larger than the gain; falsifier: flat or down on both pairs.")
