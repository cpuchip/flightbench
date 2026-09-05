"""Per-minute summary of the continuous adapter counters for one card over a window: counters_window.py HH:MM:SS HH:MM:SS [adapter]
Prints, per minute, the min and max of dedicated, shared and committed MB (card 0 = 3c6c by default) so a cell's rows can be
read against the state of the card while they ran. A cell is counter-clean when shared sits at the baseline (under ~300 MB)
and dedicated below the ceiling through its rows; a boot transient (load, profiling, capture) is expected and is not the reading."""
import sys, os, re, collections
sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
start, end = sys.argv[1], sys.argv[2]; adapter = sys.argv[3] if len(sys.argv) > 3 else "3c6c"
mins = collections.OrderedDict()
for line in open(os.path.join(HERE, "spill-counters-continuous.txt"), encoding="utf-8", errors="replace"):
    m = re.match(r"(\d\d:\d\d:\d\d) \| (.*)", line)
    if not m or not (start <= m.group(1) <= end): continue
    a = re.search(adapter + r"_phys_0 ded=(\d+) shr=(\d+) com=(\d+)", m.group(2))
    ded, shr, com = (int(a.group(1)), int(a.group(2)), int(a.group(3))) if a else (0, 0, 0)  # no instance = nothing committed
    mins.setdefault(m.group(1)[:5], []).append((ded, shr, com))
for k, v in mins.items():
    print(f"{k}  n={len(v):2d}  ded {min(x[0] for x in v):5d}-{max(x[0] for x in v):5d}  shr {min(x[1] for x in v):4d}-{max(x[1] for x in v):4d}  com {min(x[2] for x in v):5d}-{max(x[2] for x in v):5d}")
