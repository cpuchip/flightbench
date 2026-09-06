"""Round trip, stage 2b: turn the trainer's per-step dict lines into a CSV and a short summary.

Usage: python train_summary.py <train.log> <out.csv>
Lines look like: "HH:MM:SS step N: {'selector_loss_alpha': 1.0, 'acc': 0.38, ... 'loss': 1.16, ...}".
"""
import sys, re, ast, csv
sys.stdout.reconfigure(encoding="utf-8")
KEYS = ["loss", "lk_loss", "selector_loss", "selector_loss_alpha", "selector_accuracy", "selector_coverage", "acc",
        "dflash/hard_label/expected_accepted_length", "dflash/selector/serving_accepted_length",
        "grad_norm", "lr", "perf/train_compute_time_s", "perf/step_time_s"]
STEP = re.compile(r"^(\d\d:\d\d:\d\d) step (\d+): (\{.*\})\s*$")


def main():
    path, out = sys.argv[1], sys.argv[2]
    rows = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = STEP.match(line.strip())
        if not m:
            continue
        try:
            d = ast.literal_eval(m.group(3))
        except Exception:
            continue
        rows.append((m.group(1), int(m.group(2)), d))
    if not rows:
        print("train_summary: no step lines found"); return
    allkeys = sorted({k for _, _, d in rows for k in d})
    cols = [k for k in KEYS if k in allkeys] + [k for k in allkeys if k not in KEYS]
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(["time", "step"] + cols)
        for t, s, d in rows:
            w.writerow([t, s] + [d.get(k, "") for k in cols])
    def col(k):
        return [float(d[k]) for _, _, d in rows if k in d and isinstance(d[k], (int, float))]
    def mean(v): return sum(v) / len(v) if v else float("nan")
    print(f"train_summary: {len(rows)} optimizer steps (step {rows[0][1]} .. {rows[-1][1]}); CSV {out}")
    for k in ["loss", "lk_loss", "selector_loss", "acc", "dflash/hard_label/expected_accepted_length",
              "dflash/selector/serving_accepted_length", "selector_accuracy", "grad_norm"]:
        v = col(k)
        if not v:
            continue
        q = max(1, len(v) // 4)
        print(f"   {k:48s} first {mean(v[:q]):.4f}  last quarter {mean(v[-q:]):.4f}  min {min(v):.4f}  max {max(v):.4f}")
    v = col("perf/train_compute_time_s")
    if v:
        print(f"   step time (perf/train_compute_time_s): mean {mean(v):.2f}s, median {sorted(v)[len(v)//2]:.2f}s, "
              f"max {max(v):.2f}s")
    a = col("selector_loss_alpha")
    if a:
        print(f"   selector_loss_alpha: {a[0]} .. {a[-1]} (1.0 means the selector term is in the loss)")


if __name__ == "__main__":
    main()
