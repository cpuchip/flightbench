"""Arc three: score the community-drafter cells against the DFlash2 baselines on the same cohort, paired by (prompt, seed).
Reads ROW lines (the perpos client's format). Reports, per cell: rows, steady ms/step (rows after the two warm-up rows),
tokens per step (accepted/drafts + 1, row mean), round, tok/s, completions under 1024, per-position acceptance per
thousand rounds, and the paired difference in tokens per step against each baseline with a row-level t (one boot per
arm: the 32 cells are not 32 boots, so the interval is a floor on the uncertainty, per the arc-two rule).
Step costs from cells whose resolved max_model_len or capture differs from the baseline are printed but flagged."""
import sys, os, re, statistics as st
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))

def load(f):
    p = os.path.join(HERE, f)
    if not os.path.exists(p): return []
    rows = []
    for line in open(p, encoding="utf-8", errors="replace"):
        if line.startswith("ROW ") and "NO_SPEC" not in line:
            d = dict(re.findall(r"(\w+)=([0-9.]+)", line)); rows.append({k: float(v) for k, v in d.items()})
    return rows

def resolved(f):
    p = os.path.join(HERE, f)
    if not os.path.exists(p): return ""
    t = open(p, encoding="utf-8", errors="replace").read()
    m = re.search(r"RESOLVED[^\n]{0,200}", t); s = re.search(r"SEQUENCE[^\n]{0,120}", t)
    cap = re.search(r"Graph capturing finished in \d+ secs, took [0-9.]+ GiB", t)
    return (m.group(0)[:160] if m else "") + " | " + (s.group(0)[:80] if s else "") + " | " + (cap.group(0) if cap else "no capture line")

key = lambda x: (x["prompt"], x["seed"])
tps = lambda x: x["acc"] / x["drafts"] + 1

def summary(name, rows):
    if not rows: return None
    steady = [x for x in rows if not (x["seed"] == 1 and x["prompt"] in (0, 1))]
    ms = [1000 * x["wall"] / x["drafts"] for x in steady] if steady else [float("nan")]
    pk = sorted((k for k in rows[0] if re.fullmatch(r"p\d+", k)), key=lambda k: int(k[1:]))
    return dict(name=name, n=len(rows), ms=st.mean(ms), ms_lo=min(ms), ms_hi=max(ms),
                tps=st.mean(tps(x) for x in rows), rnd=st.mean(x["round"] for x in rows),
                toks=st.mean(x.get("tok_s", float("nan")) for x in rows),
                short=[(int(x["prompt"]), int(x["seed"]), int(x["out"])) for x in rows if x["out"] < 1024],
                pos=[st.mean(x[k] for x in rows) for k in pk])

def paired(a, b):
    B = {key(x): tps(x) for x in b}
    d = [tps(x) - B[key(x)] for x in a if key(x) in B]
    if len(d) < 3: return None
    m = st.mean(d); sd = st.pstdev(d) * (len(d) / (len(d) - 1)) ** 0.5; se = sd / len(d) ** 0.5
    return dict(n=len(d), mean=m, se=se, t=(m / se if se else float("nan")), worse=sum(1 for v in d if v < 0), median=st.median(d))

baselines = {"default (r7b, LOOKUP=1)": load("r7-r7b.txt"), "bl7off (LOOKUP=0)": load("drf-bl7off.txt")}
cells = ["drf-ap7sa0.txt", "drf-ap7lite.txt", "drf-bl7off.txt", "drf-ds7.txt", "drf-ap11.txt", "drf-ap15sa0.txt", "drf-ds7sa0.txt"]
print("baselines: " + ", ".join(f"{k}: {len(v)} rows" + (f", tok/step {st.mean(tps(x) for x in v):.3f}" if v else "") for k, v in baselines.items()))
for f in cells:
    rows = load(f)
    if not rows: continue
    s = summary(f[4:-4], rows)
    print(f"\n== {s['name']}: rows {s['n']}, steady ms/step {s['ms']:.1f} ({s['ms_lo']:.1f}-{s['ms_hi']:.1f}), tok/step {s['tps']:.3f}, round {s['rnd']:.3f}, tok/s {s['toks']:.1f}")
    print("   resolved:", resolved(f))
    print("   per-position per thousand rounds:", " ".join(f"{v:.0f}" for v in s["pos"]))
    print("   completions under 1024:", s["short"])
    for bname, b in baselines.items():
        if not b or f == "drf-bl7off.txt" and bname.startswith("bl7off"): continue
        pr = paired(rows, b)
        if pr: print(f"   vs {bname}: paired mean {pr['mean']:+.3f} tok/step (se {pr['se']:.3f}, t {pr['t']:+.2f}, median {pr['median']:+.3f}, worse {pr['worse']} of {pr['n']}); one boot per arm, interval is a floor")
