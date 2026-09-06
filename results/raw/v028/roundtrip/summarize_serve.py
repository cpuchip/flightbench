"""Round trip, stage 4c: per-position acceptance and paired differences across serve arms.

Usage: python summarize_serve.py <baseline.txt> <arm.txt> [<arm2.txt> ...]
Reads ROW lines (perpos_client format): tok_per_step, acc, drafts, out, wall, p0..p6 per (seed, prompt).
Prints per arm: rows, mean tok/step (mean of rows), pooled tok/step (1 + sum acc / sum drafts), decode tok/s,
per-position acceptance (sum p_k / sum drafts), and the paired difference vs the baseline on the rows both
arms have (same seed and prompt), with a sign count.
"""
import sys, re, os
sys.stdout.reconfigure(encoding="utf-8")
ROW = re.compile(r"^ROW arm=(\S+) seed=(\d+) prompt=(\d+) drafts=(\d+) dtok=(\d+) acc=(\d+) round=([\d.]+) "
                 r"tok_per_step=([\d.]+) out=(\d+) wall=([\d.]+) tok_s=([\d.]+) distinct=([\d.]+) gzip=([\d.]+)(.*)$")


def load(path):
    rows = {}
    arm = os.path.basename(path)
    for line in open(path, encoding="utf-8", errors="replace"):
        m = ROW.match(line.strip())
        if not m:
            continue
        arm = m.group(1)
        pos = {int(k): float(v) for k, v in re.findall(r"p(\d+)=([\d.]+)", m.group(14))}
        rows[(int(m.group(2)), int(m.group(3)))] = dict(drafts=int(m.group(4)), dtok=int(m.group(5)), acc=int(m.group(6)),
                                                        tps=float(m.group(8)), out=int(m.group(9)), wall=float(m.group(10)),
                                                        tok_s=float(m.group(11)), pos=pos)
    return arm, rows


def summarize(arm, rows):
    if not rows:
        print(f"{arm}: no ROW lines"); return None
    n = len(rows); D = sum(r["drafts"] for r in rows.values()); A = sum(r["acc"] for r in rows.values())
    O = sum(r["out"] for r in rows.values()); W = sum(r["wall"] for r in rows.values())
    mean_tps = sum(r["tps"] for r in rows.values()) / n
    K = max((max(r["pos"]) if r["pos"] else -1) for r in rows.values()) + 1
    perpos = [sum(r["pos"].get(k, 0.0) for r in rows.values()) / max(D, 1) for k in range(K)]
    print(f"{arm}: rows {n}, mean tok/step {mean_tps:.3f}, pooled tok/step {1 + A / max(D, 1):.3f}, "
          f"decode tok/s {O / max(W, 1e-9):.1f}, output tokens {O}")
    print("   per-position acceptance (accepted at pos k / drafts): " +
          " ".join(f"p{k}={v:.3f}" for k, v in enumerate(perpos)))
    return dict(n=n, mean_tps=mean_tps, pooled=1 + A / max(D, 1), perpos=perpos)


def main():
    base_arm, base = load(sys.argv[1])
    print(f"baseline file {sys.argv[1]}")
    summarize(base_arm, base)
    for path in sys.argv[2:]:
        arm, rows = load(path)
        print(f"\narm file {path}")
        s = summarize(arm, rows)
        if not s:
            continue
        common = sorted(set(rows) & set(base))
        if not common:
            print("   no paired rows with the baseline"); continue
        d = [rows[k]["tps"] - base[k]["tps"] for k in common]
        pos_n = sum(1 for x in d if x > 0); neg_n = sum(1 for x in d if x < 0)
        mean_d = sum(d) / len(d)
        sd = (sum((x - mean_d) ** 2 for x in d) / max(len(d) - 1, 1)) ** 0.5
        print(f"   paired vs {base_arm} on {len(common)} rows: mean tok/step diff {mean_d:+.3f} "
              f"(sd {sd:.3f}, se {sd / max(len(d), 1) ** 0.5:.3f}); rows better {pos_n}, worse {neg_n}, equal {len(d) - pos_n - neg_n}")
        bD = sum(base[k]["drafts"] for k in common); aD = sum(rows[k]["drafts"] for k in common)
        K = max(len(s["perpos"]), 7)
        bp = [sum(base[k]["pos"].get(j, 0.0) for k in common) / max(bD, 1) for j in range(K)]
        ap = [sum(rows[k]["pos"].get(j, 0.0) for k in common) / max(aD, 1) for j in range(K)]
        print("   per-position diff (arm - baseline): " + " ".join(f"p{j}={ap[j] - bp[j]:+.3f}" for j in range(K)))


if __name__ == "__main__":
    main()
