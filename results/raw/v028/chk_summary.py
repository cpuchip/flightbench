"""Arc-two re-checks under the adapter counters: chk_summary.py <cell-stem> [HH:MM:SS HH:MM:SS]
Prints the cell's steady ms/step (rows after the two warm-up rows), tok/step, tok/s and the RESOLVED line, then, if a window
is given, the per-minute counters over it (counters_window.py). The arc-two figures the three cells re-measure: std1 (width 15,
kernel on) 56.5 ms/step; the default 23.2; the forced slow-class boot 45."""
import sys, os, re, statistics as st, subprocess
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
stem = sys.argv[1]
p = os.path.join(HERE, stem + ".txt")
rows = []
for line in open(p, encoding="utf-8", errors="replace"):
    if line.startswith("ROW ") and "NO_SPEC" not in line:
        d = dict(re.findall(r"(\w+)=([0-9.]+)", line)); rows.append({k: float(v) for k, v in d.items()})
t = open(p, encoding="utf-8", errors="replace").read()
m = re.search(r"RESOLVED[^\n]{0,160}", t)
steady = [x for x in rows if not (x["seed"] == 1 and x["prompt"] in (0, 1)) and x["out"] >= 16]  # boundary rows excluded from the step cost
ms = [1000 * x["wall"] / x["drafts"] for x in steady]
print(f"{stem}: rows {len(rows)}, steady ms/step {st.mean(ms):.1f} (min {min(ms):.1f}, max {max(ms):.1f}, median {st.median(ms):.1f}), "
      f"tok/step {st.mean(x['acc']/x['drafts']+1 for x in rows):.3f}, tok/s {st.mean(x['tok_s'] for x in rows):.1f}, short rows {[(int(x['prompt']), int(x['seed']), int(x['out'])) for x in rows if x['out'] < 1024]}")
print("  " + (m.group(0) if m else "no RESOLVED line"))
if len(sys.argv) > 3:
    print(subprocess.run([sys.executable, os.path.join(HERE, "counters_window.py"), sys.argv[2], sys.argv[3]], capture_output=True, text=True).stdout)
