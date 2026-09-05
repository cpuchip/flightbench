"""Classify every cell's boot by what it loaded and compiled. Card from the engine's port in the cell file
(18020 = card 0 = volume lane0, 18021 = card 1 = lane1). Class from the captured startup lines when a
late-<cell>.txt exists (L = Directly load AOT, C = Compiling a graph, in log order), else from the number of
artefacts written on that card's volume during the boot window (first engine INFO timestamp to the file's
last write): 3 = full compile, 0 = full load, 1 or 2 = partial. Cache-disabled boots (no artefact written,
three compile lines) are labelled by their compile lines. Repaired 2026-09-05 after the third fresh-eyes
review: the first version searched for GPU UUIDs the cell files do not carry and scanned every cell against lane0."""
import sys, os, re, statistics as st, datetime as dt
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
inv = open(os.path.join(HERE, "aot-inventory-20260905.txt"), encoding="utf-8").read()
lanes = {}
for name, chunk in zip(("lane0", "lane1"), inv.split("volume qwen-cache-lane")[1:]):
    arts = []
    for m in re.finditer(r"^(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d)\.\d+ \S+ \d+ torch_aot_compile/([0-9a-f]{8})", chunk, re.M):
        arts.append((dt.datetime.fromisoformat(m.group(1) + "T" + m.group(2)), m.group(3)))
    lanes[name] = sorted(arts)
def steady(rows):
    s = [x for x in rows if not (x["seed"] == 1 and x["prompt"] in (0, 1))]
    return st.mean(1000 * x["wall"] / x["drafts"] for x in s) if s else float("nan")
skip = ("late-", "aot-", "model-", "greedy-", "nvidia", "p7-p7a-mamba")
out = []
for f in sorted(os.listdir(HERE)):
    if not f.endswith(".txt") or "-" not in f or f.startswith(skip): continue
    p = os.path.join(HERE, f)
    txt = open(p, encoding="utf-8", errors="replace").read()
    m = re.search(r"INFO (\d\d)-(\d\d) (\d\d:\d\d:\d\d)", txt)
    port = re.search(r"'port': (1802[01])", txt)
    if not m or not port: continue
    rows = []
    for line in txt.splitlines():
        if line.startswith("ROW ") and "NO_SPEC" not in line:
            d = dict(re.findall(r"(\w+)=([0-9.]+)", line)); rows.append({k: float(v) for k, v in d.items()})
    if len(rows) < 8: continue
    card = "card0" if port.group(1) == "18020" else "card1"
    lane = "lane0" if card == "card0" else "lane1"
    start = dt.datetime(2026, int(m.group(1)), int(m.group(2)), *map(int, m.group(3).split(":")))
    end = dt.datetime.fromtimestamp(os.path.getmtime(p), dt.UTC).replace(tzinfo=None)
    written = [h for t, h in lanes[lane] if start - dt.timedelta(seconds=30) <= t <= end]
    cell = f.split("-", 1)[1][:-4]
    late = os.path.join(HERE, f"late-{cell}.txt")
    seq = ""
    if os.path.exists(late):
        lt = open(late, encoding="utf-8", errors="replace").read()
        seq = "".join("L" if "Directly load AOT" in x else "C" for x in re.findall(r"Directly load AOT compilation|Compiling a graph for compile range", lt))
    compiles = len(re.findall(r"Compiling a graph for compile range", txt))
    if seq: klass = {"LLL": "full load", "CCC": "full compile", "LCC": "PARTIAL-2 (head compiled)", "LLC": "partial-1 (selector)", "LCL": "PARTIAL head-only"}.get(seq, seq)
    elif compiles == 3 and not written: klass = "full compile (cache off)"
    else: klass = {0: "full load", 3: "full compile", 1: "partial-1 (by writes)", 2: "PARTIAL-2 (by writes)"}.get(len(written), f"{len(written)} written")
    out.append((start, cell, card, steady(rows), klass, seq or "-", ",".join(written)))
print(f"{'cell':<10} {'card':<5} {'start':<8} {'ms/step':>7}  {'class':<26} {'seq':<4} written")
for start, cell, card, ms, klass, seq, written in sorted(out):
    print(f"{cell:<10} {card:<5} {start:%H:%M:%S} {ms:7.1f}  {klass:<26} {seq:<4} {written}")
