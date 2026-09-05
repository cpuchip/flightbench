"""Triton autotune winners per boot, beside each boot's steady step cost. Reads the SERVERLOG excerpt
saved in a cell file (TRITON_PRINT_AUTOTUNING=1 boots only). The engine prints, per autotuned kernel,
"Triton autotuning for function <kernel> finished after <t>s; best config selected: <config>;" possibly
split across lines. Registered reading (2026-09-05): boots on the slow side (~45 ms at width 7, 56 at
width 15) share a winner on at least one kernel that fast-side boots (~23 ms) do not have."""
import os, re, sys, statistics as st
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))

def excerpt(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    a, b = txt.find("SERVERLOG_BEGIN"), txt.find("SERVERLOG_END")
    return txt[a:b] if a >= 0 and b > a else ""

def winners(path):
    ex = re.sub(r"\(EngineCore pid=\d+\) ", "", excerpt(path)).replace("\n", " ")
    out = {}
    for m in re.finditer(r"Triton autotuning for function (\w+),?\s*(?:finished after [0-9.]+s;)?\s*best config selected: ([^;]+);", ex):
        out.setdefault(m.group(1), m.group(2).strip())
    fails = len(re.findall(r"Autotuning failed with out of resource", ex))
    return out, fails

def steady(path):
    r = []
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("ROW ") and "NO_SPEC" not in line:
            d = dict(re.findall(r"(\w+)=([0-9.]+)", line)); r.append({k: float(v) for k, v in d.items()})
    s = [x for x in r if not (x["seed"] == 1 and x["prompt"] in (0, 1))]
    return (st.mean(1000 * x["wall"] / x["drafts"] for x in s) if s else float("nan")), len(r)

files = sys.argv[1:] or sorted(f for f in os.listdir(HERE) if f.startswith(("r7-", "lkcost-t8", "lkcost-ff15", "cgn-", "tmid-", "lkcost-sa0", "ffg-")) and f.endswith(".txt"))
rows = []
for f in files:
    p = os.path.join(HERE, f)
    if not os.path.exists(p): continue
    w, fails = winners(p); ms, n = steady(p)
    rows.append((f, ms, n, w, fails))
    side = "slow" if ms > 35 else "fast"
    print(f"{f:<24} steady {ms:5.1f} ms/step ({side}, {n} rows)  kernels autotuned: {len(w)}  OOR fails: {fails}")
kernels = sorted({k for _, _, _, w, _ in rows for k in w})
print()
for k in kernels:
    print(f"== {k}")
    for f, ms, n, w, _ in rows:
        print(f"   {f:<24} {ms:5.1f}  {w.get(k, '(not autotuned in this boot)')}")
# the registered test: a kernel whose winner separates fast from slow boots
fast = [r for r in rows if r[1] <= 35 and r[3]]; slow = [r for r in rows if r[1] > 35 and r[3]]
if fast and slow:
    print("\nkernels whose winner sets separate fast from slow boots:")
    for k in kernels:
        fw = {r[3].get(k) for r in fast}; sw = {r[3].get(k) for r in slow}
        if fw and sw and not (fw & sw): print(f"   {k}: fast {fw} | slow {sw}")
    print("(none listed above means no single kernel's winner separates the sides: the race is exonerated as registered)")
