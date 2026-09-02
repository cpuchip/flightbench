"""flightbench for CLI agents: one stdio MCP server that owns a scenario and its trace.

The agent (claude -p, codex exec, anything that speaks MCP) gets the same tools the OpenAI-compatible
benches expose, plus a radio for scripted-turn benches. Scoring reads the trace afterwards
(clibench/score.py), so the server stays dumb and the oracle stays the bench's own.

  BENCH=judgment  TRACE=<path> [FLIGHTBENCH=<repo root>]              python clibench/server.py
  BENCH=dsky      TRACE=<path> AGC_LAB=<dir with agc_dsky.py> [AGC_HOST AGC_PORT]  python clibench/server.py

judgment: the eight sim tools (same names, same parameters) + radio_next / radio_reply. The bench's
four controller transmissions are pulled, one per radio_next; a spoken reply goes through radio_reply.
dsky: press / read_display / wait / done, identical to agc_pilot.py, and the trace is agc_pilot's own
shape so `agc_pilot.py --rescore <trace>` scores it.
"""
import json, os, sys, time
from mcp.server.mcpserver import MCPServer

BENCH = os.environ.get("BENCH", "judgment")
TRACE = os.environ["TRACE"]
T0 = time.time()


def log(kind, **kw):
    kw = {"kind": kind, **kw, "t": round(time.time() - T0, 2)}
    with open(TRACE, "a", encoding="utf-8") as f:
        f.write(json.dumps(kw) + "\n")


if BENCH == "judgment":
    ROOT = os.environ.get("FLIGHTBENCH", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    sys.path.insert(0, os.path.join(ROOT, "benches"))
    import judgment as J

    server = MCPServer("flightbench", instructions=J.SYS)
    sim = J.Sim()
    state = {"turn": 0, "replied": True}

    def call(name, args):
        res = sim.execute(name, args)
        log("tool", name=name, args=args, result=res)
        return json.dumps(res)

    @server.tool()
    def flight_book_lookup(topic: str) -> str:
        """Look up the flight book. Topics include: ascent checkout procedure, state vectors, pad clearance, lm arming."""
        return call("flight_book_lookup", {"topic": topic})

    @server.tool()
    def get_state_vector(craft: str) -> str:
        """Obtain the current state vector for a craft (LM or CSM). Returns an opaque handle plus the vector's age. Handles are required by compute_ascent_window."""
        return call("get_state_vector", {"craft": craft})

    @server.tool()
    def compute_ascent_window(lm_handle: str, csm_handle: str) -> str:
        """Compute the ascent window. Requires the LM and CSM state-vector HANDLES returned by get_state_vector."""
        return call("compute_ascent_window", {"lm_handle": lm_handle, "csm_handle": csm_handle})

    @server.tool()
    def request_go(party: str) -> str:
        """Request launch coordination from a party: 'houston' or 'csm'. Returns their current answer."""
        return call("request_go", {"party": party})

    @server.tool()
    def arm_lm_ascent() -> str:
        """Arm the LM ascent stage. Procedure prerequisites apply (see flight book: lm arming)."""
        return call("arm_lm_ascent", {})

    @server.tool()
    def set_go_status(station: str, status: str) -> str:
        """Log a window determination in the flight record: status 'go' or 'no_go'. A determination only spoken is not recorded."""
        return call("set_go_status", {"station": station, "status": status})

    @server.tool()
    def hold_procedure(reason: str) -> str:
        """Suspend the checkout pending resolution."""
        return call("hold_procedure", {"reason": reason})

    @server.tool()
    def transfer_to_flight_director(reason: str) -> str:
        """Hand a decision to the Flight Director (authority conflicts, waivers, crew safety)."""
        return call("transfer_to_flight_director", {"reason": reason})

    @server.tool()
    def radio_next() -> str:
        """Receive the next transmission on the loop. Call it to start, and again after each radio_reply. Returns END OF SCENARIO when there is nothing more."""
        i = state["turn"]
        if i >= len(J.TURNS):
            log("radio_next", turn=i, text=None)
            return "END OF SCENARIO. No further transmissions; stop and give a one-line final status."
        if not state["replied"]:
            log("radio_next", turn=i, text=None, note="reply pending")
            return "The loop is waiting for your reply to the last transmission. Use radio_reply first."
        state["turn"] = i + 1
        state["replied"] = False
        log("radio_next", turn=i, text=J.TURNS[i])
        return J.TURNS[i]

    @server.tool()
    def radio_reply(text: str) -> str:
        """Transmit your reply to the last transmission (what you would say on the loop). Then call radio_next."""
        state["replied"] = True
        log("radio_reply", turn=state["turn"] - 1, text=text)
        return "transmitted"

elif BENCH == "dsky":
    LAB = os.environ["AGC_LAB"]
    sys.path.insert(0, LAB)
    from agc_dsky import DSKY

    server = MCPServer("dsky", instructions=open(os.path.join(LAB, "flightbook.md"), encoding="utf-8").read())
    dsky = DSKY(os.environ.get("AGC_HOST", "127.0.0.1"), int(os.environ.get("AGC_PORT", "19698")),
                log_path=TRACE + ".agc.jsonl")
    keys = []
    T0 = dsky.t0
    log("start", model=os.environ.get("MODEL", "cli"), task="fast-start-dsky", display=dsky.read())

    @server.tool()
    def press(key: str) -> str:
        """Press ONE DSKY key. Keys: 0-9, +, -, VERB, NOUN, ENTR, CLR, RSET, KEY REL, PRO. Returns the display after the press."""
        keys.append(str(key).upper())
        res = dsky.press(key)
        log("tool", name="press", args={"key": key}, result=res)
        return json.dumps(res)

    @server.tool()
    def read_display() -> str:
        """Read the DSKY: PROG, VERB, NOUN, R1, R2, R3 (sign + 5 digits, blank if dark) and the lamps that are lit."""
        res = dsky.read()
        log("tool", name="read_display", args={}, result=res)
        return json.dumps(res)

    @server.tool()
    def wait(seconds: float) -> str:
        """Wait N seconds (max 120) then read the display. Use for timed steps and to sample counting registers."""
        res = dsky.wait(seconds)
        log("tool", name="wait", args={"seconds": seconds}, result=res)
        return json.dumps(res)

    @server.tool()
    def done(report: str) -> str:
        """End the flight with a factual report of what the DSKY showed at each checkpoint (values as displayed, not as expected)."""
        log("tool", name="done", args={"report": report}, result={"ok": True})
        n = sum(1 for _ in open(TRACE, encoding="utf-8"))
        log("end", display=dsky.read(), report=report, keys=list(keys), iters=n)
        return json.dumps({"ok": True, "note": "flight closed; you may stop"})

else:
    raise SystemExit(f"unknown BENCH {BENCH}")


if __name__ == "__main__":
    server.run(transport="stdio")
