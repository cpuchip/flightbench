"""Throwaway driver for a headless NVIDIA PAIR node: spawns nvpair-ui-broker over
stdio JSON-RPC (the TUI's wire), logs every response and notification, polls the
engine/proxy state on a cadence, and shuts the broker down when a stop file
appears or the deadline passes. Prototype instrument, not a product.
"""
import json
import os
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

sys.stdout.reconfigure(encoding="utf-8")

BIN = r"<workspace>\projects\personal-ai-router\services\build\bin"
HERE = os.path.dirname(os.path.abspath(__file__))
STOP_FILE = os.path.join(HERE, "pair-stop")
LOG = open(os.path.join(HERE, "driver.log"), "a", encoding="utf-8")
BROKER_ERR = open(os.path.join(HERE, "broker.stderr.log"), "a", encoding="utf-8")
DEADLINE_S = int(os.environ.get("PAIR_DEADLINE_S", "1800"))
POLL_S = float(os.environ.get("PAIR_POLL_S", "5"))


def stamp():
    return datetime.now(timezone.utc).strftime("%H:%M:%S.%f")[:-3] + "Z"


def log(kind, text):
    line = f"{stamp()} {kind} {text}"
    LOG.write(line + "\n")
    LOG.flush()
    print(line, flush=True)


class Broker:
    def __init__(self):
        exe = os.path.join(BIN, "nvpair-ui-broker.exe")
        self.p = subprocess.Popen(
            [exe], cwd=BIN, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=BROKER_ERR, bufsize=0,
        )
        self.next_id = 0
        self.pending = {}
        self.lock = threading.Lock()
        self.dead = threading.Event()
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        for raw in self.p.stdout:
            try:
                msg = json.loads(raw.decode("utf-8", "replace"))
            except Exception as e:
                log("badframe", f"{e}: {raw[:200]!r}")
                continue
            if "id" in msg and msg.get("method") is None:
                with self.lock:
                    ev = self.pending.pop(msg["id"], None)
                if ev is not None:
                    ev[0] = msg
                    ev[1].set()
                else:
                    log("orphan-response", json.dumps(msg)[:400])
            else:
                params = json.dumps(msg.get("params"))
                if len(params) > 600:
                    params = params[:600] + "..."
                log("notify", f"{msg.get('method')} {params}")
        self.dead.set()
        log("broker", "stdout closed")

    def call(self, method, params=None, timeout=15.0):
        with self.lock:
            self.next_id += 1
            rid = self.next_id
            ev = [None, threading.Event()]
            self.pending[rid] = ev
        req = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            req["params"] = params
        try:
            self.p.stdin.write((json.dumps(req) + "\n").encode("utf-8"))
            self.p.stdin.flush()
        except Exception as e:
            log("call-error", f"{method}: {e}")
            return None
        if not ev[1].wait(timeout):
            log("timeout", method)
            with self.lock:
                self.pending.pop(rid, None)
            return None
        msg = ev[0]
        if "error" in msg:
            log("rpc-error", f"{method}: {json.dumps(msg['error'])[:400]}")
            return {"__error__": msg["error"]}
        return msg.get("result")

    def shutdown(self):
        log("broker", "sending shutdown")
        self.call("shutdown", None, timeout=5)
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.wait(timeout=15)
            log("broker", f"exited {self.p.returncode}")
        except subprocess.TimeoutExpired:
            log("broker", "kill after grace")
            self.p.kill()


def compact(v, n=500):
    s = json.dumps(v, separators=(",", ":"))
    return s if len(s) <= n else s[:n] + "..."


def main():
    if os.path.exists(STOP_FILE):
        os.remove(STOP_FILE)
    log("driver", f"start bin={BIN} deadline={DEADLINE_S}s poll={POLL_S}s")
    b = Broker()
    t0 = time.time()
    last_status = None
    try:
        while time.time() - t0 < DEADLINE_S and not b.dead.is_set():
            if os.path.exists(STOP_FILE):
                log("driver", "stop file seen")
                break
            snap = {}
            snap["engine"] = b.call("engine:status", {"engine": "lmstudio"})
            snap["lmproxy"] = b.call("lmstudio-proxy:get-status")
            snap["models"] = b.call("engine:models", {"engine": "lmstudio"})
            snap["nodes"] = b.call("discovery:get-nodes")
            s = compact(snap, 1600)
            if s != last_status:
                log("poll", s)
                last_status = s
            else:
                log("poll", "unchanged")
            time.sleep(POLL_S)
    finally:
        b.shutdown()
        log("driver", "done")


if __name__ == "__main__":
    main()
