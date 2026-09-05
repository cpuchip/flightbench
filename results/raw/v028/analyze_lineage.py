"""Map every card-0 cell to the compile-cache artefacts written during its boot (lane0 volume), and
classify the boot as full compile (3 written), full load (0) or partial (1-2). Boot start = first
engine INFO timestamp in the cell file (UTC); end = file mtime (UTC). Steady ms/step as in
analyze_winners.py. Written 2026-09-05 after threadchip's #2097/#2098 (partial-recompile hypothesis)."""
import sys, os, re, statistics as st, datetime as dt
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
inv = open(os.path.join(HERE, "aot-inventory-20260905.txt"), encoding="utf-8").read()
lane0 = inv.split("volume qwen-cache-lane1")[0]
arts = []
for m in re.finditer(r"^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d)\.\d+ \S+ \d+ torch_aot_compile/([0-9a-f]{8})", lane0, re.M):
    arts.append((dt.datetime.fromisoformat(m.group(1) + "T" + m.group(2)), m.group(3)))
arts.sort()
def steady(rows):
    s = [x for x in rows if not (x["seed"] == 1 and x["prompt"] in (0, 1))]
    return st.mean(1000 * x["wall"] / x["drafts"] for x in s) if s else float("nan")
skip = ("late-", "aot-", "model-", "greedy-", "nvidia")
files = [f for f in os.listdir(HERE) if f.endswith(".txt") and "-" in f and not f.startswith(skip)]
rows_out = []
for f in sorted(files):
    p = os.path.join(HERE, f)
    txt = open(p, encoding="utf-8", errors="replace").read()
    m = re.search(r"INFO (\d\d)-(\d\d) (\d\d:\d\d:\d\d)", txt)
    if not m: continue
    start = dt.datetime(2026, int(m.group(1)), int(m.group(2)), *map(int, m.group(3).split(":")))
    end = dt.datetime.utcfromtimestamp(os.path.getmtime(p))
    rows = []
    for line in txt.splitlines():
        if line.startswith("ROW ") and "NO_SPEC" not in line:
            d = dict(re.findall(r"(\w+)=([0-9.]+)", line)); rows.append({k: float(v) for k, v in d.items()})
    if len(rows) < 8: continue
    card = "card1" if re.search(r"GPU-9d0861d3", txt) else ("card0" if re.search(r"GPU-206a1b8d", txt) else "card?")
    written = [h for t, h in arts if start - dt.timedelta(seconds=30) <= t <= end]
    loaded = re.findall(r"Directly load AOT compilation from path \S*torch_aot_compile/([0-9a-f]{8})", txt)
    compiled = len(re.findall(r"Compiling a graph for compile range", txt))
    rows_out.append((start, f, card, steady(rows), written, loaded, compiled))
print(f"{'cell':<22} {'card':<5} {'start(UTC)':<9} {'ms/step':>7}  written-in-window (lane0)     loaded(if captured) compiled-lines")
for start, f, card, ms, written, loaded, compiled in sorted(rows_out):
    kind = {0: "load/none", 3: "FULL", 1: "PARTIAL-1", 2: "PARTIAL-2"}.get(len(written), f"{len(written)}w")
    print(f"{f:<22} {card:<5} {start:%H:%M:%S} {ms:7.1f}  {kind:<10} {','.join(written):<28} {','.join(loaded):<28} {compiled}")
