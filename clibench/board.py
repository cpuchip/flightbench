"""Render results/cli-runs/rows.jsonl as a markdown board (one row per run; latest run per cell first).

  python clibench/board.py [rows.jsonl]
"""
import json, os, sys
from collections import OrderedDict

p = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "results", "cli-runs", "rows.jsonl")
rows = [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
ORDER = ["claude-sonnet-5", "claude-opus-5", "claude-fable-5-1", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]

def key(r):
    m = r["model"]
    return (ORDER.index(m) if m in ORDER else 99, m)

def cost(r):
    c = r.get("cost_usd")
    return f"${c:.2f}" if isinstance(c, (int, float)) else "n/a"

print("| cli | model | judgment (8 decisions) | NO-GO on | DSKY (7 checkpoints) | DSKY misses | cost (judg / dsky) | turns (judg / dsky) |")
print("|---|---|---|---|---|---|---|---|")
cells = OrderedDict()
for r in rows:
    cells.setdefault((r["cli"], r["model"]), {})[r["bench"]] = r   # last run per cell wins
for (cli, model), b in sorted(cells.items(), key=lambda kv: key({"model": kv[0][1]})):
    j, d = b.get("judgment"), b.get("dsky")
    jscore = f"**{j['n_ok']}/8 GREEN**" if j and j["n_ok"] == 8 else (f"{j['n_ok']}/8" if j else "")
    jmiss = ", ".join(k.split("-", 1)[1] for k, v in (j or {}).get("decisions", {}).items() if not v) if j else ""
    dscore = (f"**{d['score']} GREEN**" if d and d.get("score") == "7/7" else (d.get("score", "") if d else ""))
    dmiss = ", ".join(k.split("_", 1)[1] for k, v in (d or {}).get("checkpoints", {}).items() if not v) if d and d.get("checkpoints") else (d.get("note", "") if d else "")
    print(f"| {cli} | {model} | {jscore} | {jmiss} | {dscore} | {dmiss} | {cost(j) if j else 'n/a'} / {cost(d) if d else 'n/a'} | "
          f"{(j or {}).get('cli_turns', 'n/a')} / {(d or {}).get('cli_turns', 'n/a')} |")
