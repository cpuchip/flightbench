"""Score a CLI-agent trace with the bench's own oracle.

  python clibench/score.py judgment <trace.jsonl> [--cli NAME --model NAME --cost USD --turns N --wall S --out rows.jsonl]

judgment: replays the recorded tool calls, in order, through a fresh benches/judgment.Sim (the sim is
deterministic, so the replay reproduces the state the agent produced), collects the radio_reply texts
as the spoken replies, and calls judgment.score(). Prints the same GO / NO-GO lines the bench prints.
dsky: not here; use `agc_pilot.py --rescore <trace>` (the server writes agc_pilot's trace shape).
"""
import argparse, json, os, sys

ap = argparse.ArgumentParser()
ap.add_argument("bench", choices=["judgment", "mission"])
ap.add_argument("--seat", default="controller")
ap.add_argument("trace")
ap.add_argument("--cli", default="?")
ap.add_argument("--model", default="?")
ap.add_argument("--cost", type=float, default=None)
ap.add_argument("--turns", type=int, default=None)
ap.add_argument("--wall", type=float, default=None)
ap.add_argument("--out", default=None)
a = ap.parse_args()

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "benches"))
if a.bench == "mission":
    import mission as J
    sim = J.Mission(a.seat)
    n_turns = len(J.ALL_TURNS)
else:
    import judgment as J
    sim = J.Sim()
    n_turns = len(J.TURNS)

rows = [json.loads(l) for l in open(a.trace, encoding="utf-8") if l.strip()]
replies = []
radio_turns = 0
for r in rows:
    if r["kind"] == "tool" and r.get("forced"):
        continue                                   # reproduced by on_turn below
    if r["kind"] == "radio_next" and r.get("text") and hasattr(sim, "on_turn"):
        sim.on_turn(r["turn"])
    if r["kind"] == "tool":
        res = sim.execute(r["name"], r["args"])
        if res != r["result"]:
            print(f"REPLAY MISMATCH at call {len(sim.trace)-1} {r['name']}: recorded {r['result']} replayed {res}")
            sys.exit(2)
    elif r["kind"] == "radio_reply":
        replies.append(r.get("text") or "")
    elif r["kind"] == "radio_next" and r.get("text"):
        radio_turns += 1

D = J.score(sim, replies)
for k, v in D.items():
    print(f"[{'GO ' if v else 'NO-GO'}] {k}")
print(f"\ntrace ({len(sim.trace)} calls): " + " -> ".join(n for _, n, _, _ in sim.trace))
if a.bench == "judgment":
    print(f"csm_fetches={sim.csm_fetches} stale_computes={sim.stale_computes} bad_handles={sim.bad_handles} "
          f"houston@{sim.houston_go_at} csm_confirm@{sim.csm_confirm_at} armed@{sim.armed_at} logged={sim.go_logged} "
          f"radio_turns_pulled={radio_turns}/{n_turns} replies={len(replies)}")
else:
    print(f"burns={[(b[1], b[3], b[4]) for b in sim.burns]} logged={sim.logged} bad_refs={sim.bad_refs} landed={sim.descent['landed']} "
          f"aborted={sim.descent['aborted']} radio_turns_pulled={radio_turns}/{n_turns} replies={len(replies)}")
n_ok = sum(D.values())
verdict = "GREEN" if n_ok == len(D) else "NO-GO: " + ", ".join(k for k, v in D.items() if not v)
print(f"\n=== {a.bench}/cli {a.cli} {a.model} · {n_ok}/{len(D)} · {verdict} ===")
if a.out:
    with open(a.out, "a", encoding="utf-8") as f:
        f.write(json.dumps({"bench": a.bench, "cli": a.cli, "model": a.model, "decisions": D, "n_ok": n_ok,
                            "trace_len": len(sim.trace), "radio_turns": radio_turns, "replies": len(replies),
                            "cost_usd": a.cost, "cli_turns": a.turns, "wall_s": a.wall, "trace": a.trace}) + "\n")
