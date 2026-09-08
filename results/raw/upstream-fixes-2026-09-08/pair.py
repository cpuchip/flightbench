"""Paired comparison of two cohort arms (same 8 prompts x same seeds): rows matched by (seed, prompt).
usage: pair.py <A.txt> <B.txt>   prints per-row deltas B-A for tok/step and tok/s, mean, sd, paired t, and drafts-weighted acceptance."""
import re, sys, statistics, math
sys.stdout.reconfigure(encoding="utf-8")
R = re.compile(r"ROW arm=(\S+) seed=(\d+) prompt=(\d+) drafts=(\d+) dtok=(\d+) acc=(\d+) round=([0-9.]+) tok_per_step=([0-9.]+) out=(\d+) wall=([0-9.]+) tok_s=([0-9.]+) distinct=([0-9.]+) gzip=([0-9.]+)")
def rows(p):
    out = {}
    for line in open(p, encoding="utf-8", errors="replace"):
        m = R.search(line)
        if m:
            out[(int(m.group(2)), int(m.group(3)))] = dict(arm=m.group(1), drafts=int(m.group(4)), dtok=int(m.group(5)), acc=int(m.group(6)),
                tps=float(m.group(8)), toks=float(m.group(11)), distinct=float(m.group(12)), gzip=float(m.group(13)))
    return out
A, B = rows(sys.argv[1]), rows(sys.argv[2])
keys = sorted(set(A) & set(B))
if not keys: sys.exit("no matched rows")
def summ(name, key):
    d = [B[k][key] - A[k][key] for k in keys]
    m = statistics.mean(d); sd = statistics.stdev(d) if len(d) > 1 else float("nan")
    t = m / (sd / math.sqrt(len(d))) if sd and sd == sd else float("nan")
    ma = statistics.mean(A[k][key] for k in keys); mb = statistics.mean(B[k][key] for k in keys)
    print(f"{name:12} A={ma:.3f} B={mb:.3f} delta={m:+.3f} sd={sd:.3f} n={len(d)} paired t={t:+.2f}")
print(f"A={A[keys[0]]['arm']}  B={B[keys[0]]['arm']}  matched rows={len(keys)}")
summ("tok/step", "tps"); summ("tok/s", "toks"); summ("distinct", "distinct"); summ("gzip", "gzip")
for name, S in (("A", A), ("B", B)):
    D = sum(S[k]["drafts"] for k in keys); dt = sum(S[k]["dtok"] for k in keys); ac = sum(S[k]["acc"] for k in keys)
    print(f"{name}: drafts={D} drafted_tokens={dt} accepted={ac} acceptance/drafted={ac/dt:.4f} accepted/draft={ac/D:.3f}")
print("per-prompt delta tok/step (B-A, mean over seeds):")
for p in sorted({k[1] for k in keys}):
    ks = [k for k in keys if k[1] == p]
    print(f"  prompt {p}: {statistics.mean(B[k]['tps']-A[k]['tps'] for k in ks):+.3f}  (A {statistics.mean(A[k]['tps'] for k in ks):.3f})")
