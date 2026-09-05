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
    import statistics as _st
    rs = list(rows.values())
    # mean of per-row values, the same definition analyze_arc2.py uses for the width and cheapctx tables
    return {"tps": _st.mean(1 + r["acc"] / r["drafts"] for r in rs), "tok_s": _st.mean(r["tok_s"] for r in rs),
            "ms": _st.mean(1000 * r["wall"] / r["drafts"] for r in rs), "round": N / R, "rows": len(rows), "R": R,
            "pos": {k: 1000 * v / R for k, v in sorted(pos.items())}}

boots = {}
for n in ("std1", "blk1", "blk2", "std2", "std1b", "std7", "blk7"):
    rows, res = load(n)
    if len(rows) >= 8: boots[n] = (agg(rows), res, rows)
print(f"boots in: {list(boots)}")
for n, (a, res, _) in boots.items():
    print(f"  {n:<5} rows={a['rows']:2d} rounds={a['R']:5.0f} tok/step={a['tps']:.3f} tok/s={a['tok_s']:6.1f} ms/step={a['ms']:5.1f} round={a['round']:.3f} | {res[:110]}")
pairs = [("std1", "blk1"), ("std2", "blk2"), ("std7", "blk7")]
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

# ---- boot replay check (threadchip 2026-09-05: on the other box two boots of one config were
# bit-identical on every counter). Here boots of one config replay MOST rows and diverge on a few
# (cc0 vs coh-flag 28/32, pol-sticky0 vs pol-zrev 20/32), consistent with the autotune winner set
# changing per boot (#75) and flipping a rounding tie somewhere in a minority of trajectories.
# So the reading is: std1 vs std2 identity = the box's replay rate (control); blk vs std identity
# near that rate = block verification is a NO-OP on this path (the finding would be the null);
# blk vs std identity far below it = block verification changes acceptance decisions, and only then
# do the aggregates above mean anything. Rows are compared on (drafts, acc, dtok, out).
names = [n for n in ("std1", "blk1", "blk2", "std2") if n in boots]
# trajectory signature: what was generated and accepted. Drafted tokens (dtok) are EXCLUDED: the adaptive
# block-length policy carries state between requests (the sticky coast), so dtok can differ between two
# boots that generated identical text; a signature holding it reports order effects as divergence.
def key(r): return (r["drafts"], r["acc"], r["out"])
def dtok_only(a, b): return key(a) == key(b) and a["dtok"] != b["dtok"]
print("row identity matrix (identical / shared):")
for i, a in enumerate(names):
    for b in names[i+1:]:
        ra, rb = boots[a][2], boots[b][2]; ks = set(ra) & set(rb)
        same = sum(1 for k in ks if key(ra[k]) == key(rb[k]))
        tag = "control (same config)" if a[:3] == b[:3] else "treatment vs control"
        donly = sum(1 for k in ks if dtok_only(ra[k], rb[k]))
        print(f"  {a} vs {b}: {same}/{len(ks)} identical trajectories  (+{donly} rows equal except drafted tokens)  [{tag}]")
