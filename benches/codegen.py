import sys
sys.stdout.reconfigure(encoding='utf-8')
"""Flightbench v5: the model CODES part of the launch. It gets the flight
book's constraints and must write evaluate_launch(state) -> (decision,
reason); a deterministic oracle runs 14 cases against the function,
including every trap the tool benches carry. Score = cases passed.
Env: BASE, MODEL, THINK, OUT."""
import json, os, re, time, urllib.request

BASE = os.environ.get("BASE", "http://127.0.0.1:8143/v1")
MODEL = os.environ.get("MODEL", "model")
THINK = os.environ.get("THINK", "off")
OUT = os.environ.get("OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results", "raw", "v5-results.jsonl"))
MAXTOK = 1200 if THINK == "off" else 2800  # default-reasoning models (THINK=none) burn budget thinking

PROMPT = """You are writing flight software for an Apollo-era launch simulation.

Flight book constraints:
- A state vector OLDER than 30 minutes is EXPIRED. Expired data is unusable.
- A launch window may be worked only if it opens no sooner than 45 minutes
  from now (opening at exactly 45 is acceptable).
- Arming and a GO require BOTH: Houston answering 'GO' and the CSM answering
  'CONFIRMED'. Any other answer (including 'STAND BY') is not affirmative.

Decision rules, in precedence order:
1. If any state vector is expired, the decision is 'hold' (data unusable).
2. Otherwise, if the window fails clearance OR the confirms are not both
   affirmative, the decision is 'no_go'.
3. Otherwise 'go'.

Write a single Python function:

    def evaluate_launch(state: dict) -> tuple:

state has keys: lm_vector_age_min (number), csm_vector_age_min (number),
window_opens_in_min (number), houston (str), csm (str).
Return (decision, reason): decision is exactly 'go', 'no_go', or 'hold';
reason is a short string. No imports, no I/O. Output ONLY one Python code
block containing the function."""

CASES = [
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 5, "window_opens_in_min": 60, "houston": "GO", "csm": "CONFIRMED"}, "go"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 122, "window_opens_in_min": 60, "houston": "GO", "csm": "CONFIRMED"}, "hold"),
 ({"lm_vector_age_min": 45, "csm_vector_age_min": 5, "window_opens_in_min": 60, "houston": "GO", "csm": "CONFIRMED"}, "hold"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 5, "window_opens_in_min": 41, "houston": "GO", "csm": "CONFIRMED"}, "no_go"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 5, "window_opens_in_min": 44, "houston": "GO", "csm": "CONFIRMED"}, "no_go"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 5, "window_opens_in_min": 45, "houston": "GO", "csm": "CONFIRMED"}, "go"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 30, "window_opens_in_min": 60, "houston": "GO", "csm": "CONFIRMED"}, "go"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 31, "window_opens_in_min": 60, "houston": "GO", "csm": "CONFIRMED"}, "hold"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 5, "window_opens_in_min": 60, "houston": "GO", "csm": "STAND BY"}, "no_go"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 5, "window_opens_in_min": 60, "houston": "NO", "csm": "CONFIRMED"}, "no_go"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 200, "window_opens_in_min": 10, "houston": "NO", "csm": "STAND BY"}, "hold"),
 ({"lm_vector_age_min": 1, "csm_vector_age_min": 1, "window_opens_in_min": 200, "houston": "GO", "csm": "CONFIRMED"}, "go"),
 ({"lm_vector_age_min": 29, "csm_vector_age_min": 29, "window_opens_in_min": 46, "houston": "GO", "csm": "CONFIRMED"}, "go"),
 ({"lm_vector_age_min": 5, "csm_vector_age_min": 5, "window_opens_in_min": 60, "houston": "GO", "csm": ""}, "no_go"),
]

def call_model():
    payload = {"model": MODEL, "messages": [{"role": "user", "content": PROMPT}],
               "max_tokens": MAXTOK, "temperature": 0}
    if THINK in ("on", "off"):
        payload["chat_template_kwargs"] = {"enable_thinking": THINK == "on"}
    req = urllib.request.Request(f"{BASE}/chat/completions",
        data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                j = json.loads(r.read().decode())
            return j["choices"][0]["message"].get("content") or ""
        except Exception:
            if attempt == 2: raise
            time.sleep(3)

t0 = time.perf_counter()
text = call_model()
wall = round(time.perf_counter() - t0, 1)
m = re.search(r"```(?:python)?\s*\n(.*?)```", text, re.S)
code = m.group(1) if m else (text if "def evaluate_launch" in text else "")
passed, fails, err = 0, [], None
if code:
    ns = {}
    try:
        exec(compile(code, "<candidate>", "exec"), {"__builtins__": {"len": len, "str": str,
             "float": float, "int": int, "isinstance": isinstance, "tuple": tuple,
             "dict": dict, "bool": bool, "abs": abs, "min": min, "max": max}}, ns)
        fn = ns.get("evaluate_launch")
        if not fn:
            err = "no evaluate_launch defined"
        else:
            for i, (state, want) in enumerate(CASES, 1):
                try:
                    out = fn(dict(state))
                    got = str(out[0]).strip().lower() if isinstance(out, (tuple, list)) and out else str(out).lower()
                    if got == want: passed += 1
                    else: fails.append(f"case{i}: want {want} got {got}")
                except Exception as e:
                    fails.append(f"case{i}: raised {type(e).__name__}")
    except Exception as e:
        err = f"compile/exec: {type(e).__name__}: {e}"
else:
    err = "no code block produced"

for f in fails[:6]: print("  FAIL", f)
if err: print("  ERROR:", err)
verdict = "GREEN — FLIGHT SOFTWARE ACCEPTED" if passed == len(CASES) else "NO-GO"
print(f"=== V5-CODEGEN {MODEL} (think={THINK}) · {passed}/{len(CASES)} cases · wall {wall}s · {verdict} ===")
with open(OUT, "a", encoding="utf-8") as f:
    f.write(json.dumps({"model": MODEL, "think": THINK, "passed": passed,
                        "total": len(CASES), "wall_s": wall, "error": err,
                        "fails": fails, "code_chars": len(code)}) + "\n")
