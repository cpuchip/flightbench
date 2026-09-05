"""Which AOT artefacts each boot loaded, beside its steady step cost. Reads late-<name>.txt (the watcher's
last grep of the cell's engine log) for "Directly load AOT compilation from path .../<hash>" lines and the
cell's ROW lines for the step cost. Registered (2026-09-05 15:25Z): fast and slow default-width boots load
different artefact paths for at least one graph; identical paths on both sides exonerate the loader."""
import os, re, sys, statistics as st
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
def steady(cellfile):
    r = []
    try:
        for line in open(cellfile, encoding="utf-8", errors="replace"):
            if line.startswith("ROW ") and "NO_SPEC" not in line:
                d = dict(re.findall(r"(\w+)=([0-9.]+)", line)); r.append({k: float(v) for k, v in d.items()})
    except FileNotFoundError: return float("nan"), 0
    s = [x for x in r if not (x["seed"] == 1 and x["prompt"] in (0, 1))]
    return (st.mean(1000 * x["wall"] / x["drafts"] for x in s) if s else float("nan")), len(r)
prefix = {"r7": "r7-", "cgn7": "cgn-", "q16_7": "tmid-", "t11": "tmid-", "sa0_7": "sa07-", "pc0": "pc-", "p7": "p7-", "g7t": "g7t-"}
rows = []
for f in sorted(os.listdir(HERE)):
    m = re.match(r"late-(.+)\.txt$", f)
    if not m: continue
    name = m.group(1); txt = open(os.path.join(HERE, f), encoding="utf-8", errors="replace").read()
    paths = re.findall(r"Directly load AOT compilation from path \S*/torch_aot_compile/([0-9a-f]+)", txt)
    cold = len(re.findall(r"(?i)compiling|Dynamo bytecode", txt))
    cell = next((os.path.join(HERE, p + name + ".txt") for k, p in prefix.items() if name.startswith(k) and os.path.exists(os.path.join(HERE, p + name + ".txt"))), None)
    ms, n = steady(cell) if cell else (float("nan"), 0)
    rows.append((name, ms, n, paths, cold))
    print(f"{name:<8} steady {ms:5.1f} ms/step ({n} rows)  AOT artefacts loaded: {[p[:8] for p in paths]}  compile lines: {cold}")
fast = [r for r in rows if r[1] <= 35 and r[3]]; slow = [r for r in rows if r[1] > 35 and r[3]]
if fast and slow:
    fs = {tuple(r[3]) for r in fast}; ss = {tuple(r[3]) for r in slow}
    print("\nartefact sets, fast:", [[p[:8] for p in t] for t in fs]); print("artefact sets, slow:", [[p[:8] for p in t] for t in ss])
    print("SEPARATES" if not (fs & ss) else "does not separate: the loader is exonerated")
