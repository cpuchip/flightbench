"""Read arm 1 (width-w*.txt) and arm 2 (cheapctx-cc*.txt) rows and report, per arm:
tok/step and decode tok/s (mean, paired vs the reference arm), round, the per-position
acceptance curve (accepted at position p / rounds in which p existed is NOT recoverable from
cumulative counters, so report accepted-per-position per 1000 rounds and the share by position),
and the degeneracy guard. Paired comparisons use (seed, prompt) cells; a cell is dropped from
every arm if degenerate in any arm (distinct < 0.20 or round > 1.2 * drafter width)."""
import glob, os, re, statistics as st, sys
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))

def load(path):
    rows = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        if not line.startswith("ROW "): continue
        d = dict(re.findall(r"(\w+)=([0-9.]+)", line))
        if "drafts" not in d: continue
        k = (int(float(d["seed"])), int(float(d["prompt"])))
        rows[k] = {a: float(b) for a, b in d.items()}
    return rows

def tps(r): return 1 + r["acc"] / r["drafts"]
def width_of(r): return 7 if r["round"] >= 6.5 else round(r["round"])

def report(prefix, order, ref, label):
    arms = {}
    for name in order:
        p = os.path.join(HERE, f"{prefix}-{name}.txt")
        if os.path.exists(p):
            rows = load(p)
            if len(rows) >= 8: arms[name] = rows   # skip arms still being written
    if not arms: print(f"{label}: no data"); return
    keys = set.intersection(*(set(v) for v in arms.values())) if len(arms) > 1 else set(next(iter(arms.values())))
    bad = set()
    for name, rows in arms.items():
        for k in keys:
            r = rows[k]; w = width_of(r)
            # round size is the TREATMENT in the cheap-context arm (the long block is forced), so the
            # guard there is text-only; elsewhere round inflation is the degeneracy signal.
            if r.get("distinct", 1) < 0.20 or (prefix != "cheapctx" and r["round"] > 1.2 * w): bad.add(k)
    keys = sorted(keys - bad)
    if len(keys) < 2: print(f"{label}: fewer than 2 paired cells across {list(arms)}"); return
    print(f"\n{label}: arms {list(arms)} | paired cells {len(keys)} (guarded out {len(bad)})")
    print(f"{'arm':<9} {'tok/step':>8} {'tok/s':>7} {'round':>6} | {'d tok/step':>11} {'t':>6} | {'d tok/s':>8} {'t':>6}")
    base = arms.get(ref)
    for name, rows in arms.items():
        m_t = st.mean(tps(rows[k]) for k in keys); m_s = st.mean(rows[k]["tok_s"] for k in keys); m_r = st.mean(rows[k]["round"] for k in keys)
        line = f"{name:<9} {m_t:8.3f} {m_s:7.1f} {m_r:6.3f}"
        if base is not None and name != ref and len(keys) > 2:
            dt = [tps(rows[k]) - tps(base[k]) for k in keys]; ds = [rows[k]["tok_s"] - base[k]["tok_s"] for k in keys]
            line += f" | {st.mean(dt):+11.3f} {st.mean(dt)/(st.stdev(dt)/len(dt)**0.5):+6.2f} | {st.mean(ds):+8.1f} {st.mean(ds)/(st.stdev(ds)/len(ds)**0.5):+6.2f}"
        print(line)
    print("per-position accepted per 1000 rounds (share of all accepted in brackets):")
    for name, rows in arms.items():
        tot_rounds = sum(rows[k]["drafts"] for k in keys); tot_acc = sum(rows[k]["acc"] for k in keys)
        pos = {}
        for k in keys:
            for a, b in rows[k].items():
                if a.startswith("p") and a[1:].isdigit(): pos[int(a[1:])] = pos.get(int(a[1:]), 0) + b
        cells = [f"p{p}={1000*v/tot_rounds:.0f}[{100*v/tot_acc:.1f}%]" for p, v in sorted(pos.items()) if v > 0]
        print(f"  {name:<9} " + " ".join(cells))

report("width", ["w7", "w6", "w5", "w4", "w3"], "w7", "ARM 1 draft width (ref w7)")
report("cheapctx", ["cc0", "cc4096", "cc8192", "cc16384"], "cc0", "ARM 2 cheap-context threshold (ref cc0)")
print("\nregistered: |t|>=3 established, 2-3 suggestive, <2 not. H2 for arm 2 predicts p7..p14 share stays under ~2% even at cc16384.")
