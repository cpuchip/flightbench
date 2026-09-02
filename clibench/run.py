"""Run a flightbench scenario through a CLI coding agent and score it with the bench's own oracle.

  python clibench/run.py --cli claude --model claude-sonnet-5 --bench judgment
  python clibench/run.py --cli codex  --model gpt-5.6-luna    --bench dsky --agc-lab <dir>

claude: `claude -p` with the bench MCP server only (--strict-mcp-config, built-in tools off), the bench
system text appended to Claude Code's own system prompt, tools pre-allowed, JSON result captured.
codex:  `codex exec` with the server passed as -c overrides, --approve-for-me (an unattended read-only
or workspace-write sandbox cancels every MCP call), the bench system text as AGENTS.md in the run dir.
Both run in an empty working directory. The agent's harness (its own system prompt and loop) is part of
what is measured; the model id is the row.

judgment is scored by replay (clibench/score.py). dsky needs a live yaAGC (agc-lab container) and is
scored by agc_pilot.py --rescore; the AGC is restarted fresh before every flight.
"""
import argparse, json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

ap = argparse.ArgumentParser()
ap.add_argument("--cli", choices=["claude", "codex"], required=True)
ap.add_argument("--model", required=True)
ap.add_argument("--bench", choices=["judgment", "dsky"], required=True)
ap.add_argument("--runs", default=os.path.join(ROOT, "results", "cli-runs"))
ap.add_argument("--agc-lab", default=os.environ.get("AGC_LAB", ""))
ap.add_argument("--agc-port", type=int, default=19698)
ap.add_argument("--agc-container", default="agc-lab")
ap.add_argument("--max-turns", type=int, default=80)
ap.add_argument("--timeout", type=int, default=1500)
ap.add_argument("--tag", default="")
a = ap.parse_args()

JUDGMENT_SYS = ("You are the flight-control assistant on the EECOM loop for an Apollo-era simulation. Work strictly "
                "by the flight book; look up what you do not know. Use tools for every real action; never claim or "
                "fabricate a step. Be brief and procedural.")
JUDGMENT_PROMPT = ("You are on the loop. Call radio_next to receive the first transmission. Act on each transmission "
                   "using the tools, transmit your spoken reply with radio_reply, then call radio_next for the next one. "
                   "Continue until radio_next returns END OF SCENARIO, then stop with a one-line final status.")
DSKY_PROMPT = (
    "You are the LM pilot at the DSKY of a freshly started Apollo Guidance Computer running Luminary 099. "
    "The LM simulator IMU is NOT powered and crew switches are not available to you: DSKY keys only. "
    "Work strictly by the flight book (it is the dsky server's instructions). Checkpoints, in order:\n"
    "1. Reset the AGC (section 0.1).\n"
    "2. Bring it to the idle loop and CONFIRM that PROG shows 00 on the display (section 0.1).\n"
    "3. Run the DSKY lamp test (section 4.0) and REPORT which digits and lamps lit, then let it end.\n"
    "4. Display the AGC clock (V16N36E) and CONFIRM it is counting by reading twice a few seconds apart; report both readings.\n"
    "5. Monitor the gimbal angles (section 1.6) and report the three registers exactly as shown.\n"
    "6. Call done with a report that quotes the display readings.\n"
    "Rules: one key per press call; read_display after every ENTR; if OPR ERR lights, recover with RSET before continuing; "
    "never report a value you did not read. Stop after done returns.")

ts = time.strftime("%Y%m%d-%H%M%S")
tag = f"{a.bench}_{a.cli}_{a.model.replace('/', '_')}" + (f"_{a.tag}" if a.tag else "") + f"_{ts}"
rd = os.path.join(a.runs, tag)
work = os.path.join(rd, "work")
os.makedirs(work, exist_ok=True)
trace = os.path.join(rd, "flight.trace.jsonl")   # agc_pilot --rescore derives its output name by stripping .trace.jsonl
env = {"BENCH": a.bench, "TRACE": trace.replace("\\", "/"), "FLIGHTBENCH": ROOT.replace("\\", "/"), "MODEL": a.model}
if a.bench == "dsky":
    assert a.agc_lab, "--agc-lab (dir with agc_dsky.py, flightbook.md, agc_pilot.py) is required for dsky"
    env.update({"AGC_LAB": a.agc_lab.replace("\\", "/"), "AGC_PORT": str(a.agc_port)})
    sys_text = open(os.path.join(a.agc_lab, "flightbook.md"), encoding="utf-8").read()
    sys_text = "You fly a real AGC through its DSKY using the tools. The flight book below is authoritative; do not invent verbs or nouns.\n\n" + sys_text
    prompt = DSKY_PROMPT
    server_name = "dsky"
    # a fresh AGC per flight (the README recipe): relaunch yaAGC detached, then wait for the port
    # the README recipe: kill the old core, relaunch DETACHED (a non-detached exec's child dies with the
    # session), readiness = a yaAGC process AND packets received after a stimulus (docker-proxy accepts
    # TCP with nothing listening inside, so a connect is a false green)
    subprocess.run(["docker", "exec", a.agc_container, "sh", "-c",
                    "for p in $(ps -eo pid,comm | awk '$2==\"yaAGC\"{print $1}'); do kill $p; done; sleep 1; true"], capture_output=True)
    subprocess.run(["docker", "exec", "-d", a.agc_container, "sh", "-c",
                    "cd /opt/virtualagc-dist && nohup ./bin/yaAGC --core=Resources/source/Luminary099/Luminary099.bin "
                    "--port=19697 --cfg=Resources/LM.ini --no-resume --nodebug > /tmp/yaAGC.log 2>&1"], capture_output=True)
    sys.path.insert(0, a.agc_lab)
    from agc_dsky import DSKY
    ready = False
    for i in range(30):
        time.sleep(2)
        alive = subprocess.run(["docker", "exec", a.agc_container, "sh", "-c", "ps -eo comm | grep -c '^yaAGC$'"],
                               capture_output=True, text=True).stdout.strip()
        if alive == "0":
            continue
        try:
            d = DSKY("127.0.0.1", a.agc_port)
            d.press("RSET"); d.wait(1.5)
            got = len(d.raw) > 0
            d.close()
            if got:
                ready = True; break
        except Exception:
            pass
    assert ready, "yaAGC did not come up on the DSKY port (no packets after RSET)"
    print(f"[{tag}] fresh AGC ready")
else:
    sys_text = JUDGMENT_SYS
    prompt = JUDGMENT_PROMPT
    server_name = "flightbench"

server = os.path.join(HERE, "server.py").replace("\\", "/")
t0 = time.time()
if a.cli == "claude":
    cfg = os.path.join(rd, "mcp.json")
    json.dump({"mcpServers": {server_name: {"command": "python", "args": [server], "env": env}}}, open(cfg, "w"))
    sysf = os.path.join(rd, "system.txt"); open(sysf, "w", encoding="utf-8").write(sys_text)   # the flight book exceeds the Windows command line
    cmd = ["claude", "-p", "--model", a.model, "--append-system-prompt-file", sysf,
           "--mcp-config", cfg, "--strict-mcp-config", "--tools", "", "--allowedTools", f"mcp__{server_name}__*",
           "--output-format", "json", "--max-turns", str(a.max_turns), "--no-session-persistence"]
else:
    open(os.path.join(work, "AGENTS.md"), "w", encoding="utf-8").write(sys_text)
    env_toml = "{" + ", ".join(f'{k}="{v}"' for k, v in env.items()) + "}"
    cmd = ["codex", "exec", "-m", a.model, "--skip-git-repo-check", "--ephemeral", "--ignore-user-config",
           "--approve-for-me", "-c", f'mcp_servers.{server_name}.command="python"',
           "-c", f'mcp_servers.{server_name}.args=["{server}"]', "-c", f"mcp_servers.{server_name}.env={env_toml}",
           "--json", "-"]
open(os.path.join(rd, "cmd.txt"), "w", encoding="utf-8").write(" ".join(cmd))
try:
    # the prompt goes in on stdin: a multi-line prompt on the command line is split by the Windows shell
    p = subprocess.run(cmd, cwd=work, input=prompt, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=a.timeout, shell=(os.name == "nt"))
    out, err, rc = p.stdout, p.stderr, p.returncode
except subprocess.TimeoutExpired as e:
    out, err, rc = (e.stdout or ""), (e.stderr or "") + "\nTIMEOUT", -9
wall = round(time.time() - t0, 1)
open(os.path.join(rd, "cli.out"), "w", encoding="utf-8").write(out)
open(os.path.join(rd, "cli.err"), "w", encoding="utf-8").write(err)

cost = turns = None; result = ""; tokens = None
if a.cli == "claude":
    try:
        j = json.loads(out[out.index("{"):])
        cost, turns, result = j.get("total_cost_usd"), j.get("num_turns"), (j.get("result") or "")
    except Exception:
        result = out[-400:]
else:
    # codex --json: one JSON event per line; the last agent message is the result, token usage where reported
    for line in out.splitlines():
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") in ("item.completed",) and isinstance(ev.get("item"), dict) and ev["item"].get("type") == "agent_message":
            result = ev["item"].get("text") or result
        if ev.get("type") == "turn.completed" and isinstance(ev.get("usage"), dict):
            tokens = ev["usage"]
    turns = sum(1 for l in out.splitlines() if '"type": "item.completed"' in l or '"type":"item.completed"' in l) or None
print(f"[{tag}] cli rc={rc} wall={wall}s turns={turns} cost={cost} tokens={tokens}\n  result: {result[:300]}")

# ---- score with the bench's own oracle ----
if a.bench == "judgment":
    sc = subprocess.run([sys.executable, os.path.join(HERE, "score.py"), "judgment", trace, "--cli", a.cli, "--model", a.model,
                         "--out", os.path.join(a.runs, "rows.jsonl")] + (["--cost", str(cost)] if cost is not None else [])
                        + (["--turns", str(turns)] if turns is not None else []) + ["--wall", str(wall)],
                        capture_output=True, text=True, encoding="utf-8", errors="replace")
    print(sc.stdout[-1200:]); open(os.path.join(rd, "score.txt"), "w", encoding="utf-8").write(sc.stdout + sc.stderr)
else:
    has_end = any('"kind": "end"' in l for l in open(trace, encoding="utf-8")) if os.path.exists(trace) else False
    if not has_end:
        print(f"[{tag}] no done() call: flight not closed; scoring as 0 with the trace kept")
        row = {"bench": "dsky", "cli": a.cli, "model": a.model, "score": "0/7", "note": "no done() call", "cost_usd": cost, "cli_turns": turns, "wall_s": wall, "trace": trace}
    else:
        sc = subprocess.run([sys.executable, os.path.join(a.agc_lab, "agc_pilot.py"), "--rescore", trace, "--model", a.model],
                            capture_output=True, text=True, encoding="utf-8", errors="replace")
        open(os.path.join(rd, "score.txt"), "w", encoding="utf-8").write(sc.stdout + sc.stderr)
        try:
            s = json.loads(sc.stdout[sc.stdout.index("{"):])
            row = {"bench": "dsky", "cli": a.cli, "model": a.model, "score": s["score"], "checkpoints": s["checkpoints"], "keys": len(s["keys"]),
                   "opr_err_events": s["opr_err_events"], "cost_usd": cost, "cli_turns": turns, "wall_s": wall, "trace": trace}
        except Exception:
            row = {"bench": "dsky", "cli": a.cli, "model": a.model, "score": "?", "note": "rescore failed", "cost_usd": cost, "cli_turns": turns, "wall_s": wall, "trace": trace}
            print(sc.stdout[-600:], sc.stderr[-600:])
    print(f"=== dsky/cli {a.cli} {a.model} · {row['score']} · {row.get('checkpoints', row.get('note'))} ===")
    with open(os.path.join(a.runs, "rows.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")
