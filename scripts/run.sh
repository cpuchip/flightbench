#!/bin/bash
# Run one model through the full flightbench battery on a local llama.cpp
# server, appending JSONL rows to results/raw/.
#
# Usage:
#   bash scripts/run.sh <alias> <gguf-path> [--server-args "<extra llama-server args>"] [--think on|off|none] [--port 8143] [--llama-server <path>]
#
# Examples:
#   bash scripts/run.sh qwen3.8-q4 ~/models/Qwen3.8-27B-Q4_K_M.gguf --think off
#   bash scripts/run.sh big-moe ~/models/model.gguf --server-args "--n-cpu-moe 12"
#
# Any OpenAI-compatible endpoint works without this script: point BASE at it
# and run the benches directly (BASE=http://host:port/v1 MODEL=alias python benches/judgment.py).
set -u
ALIAS="${1:?alias required}"; MODELPATH="${2:?gguf path required}"; shift 2
EXTRA=""; THINK="none"; PORT=8143; LSRV="llama-server"
while [ $# -gt 0 ]; do case "$1" in
  --server-args) EXTRA="$2"; shift 2;;
  --think) THINK="$2"; shift 2;;
  --port) PORT="$2"; shift 2;;
  --llama-server) LSRV="$2"; shift 2;;
  *) echo "unknown arg $1"; exit 1;;
esac; done
HERE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$HERE/results/raw" "$HERE/results/logs"

"$LSRV" -m "$MODELPATH" --port "$PORT" --host 127.0.0.1 -ngl 999 $EXTRA -c 16384 --jinja -a "$ALIAS" > "$HERE/results/logs/$ALIAS.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" 2>/dev/null)
  [ "$code" = "200" ] && break; sleep 5
done
[ "$code" = "200" ] || { echo "server never became healthy; see results/logs/$ALIAS.log"; exit 1; }

export BASE="http://127.0.0.1:$PORT/v1" MODEL="$ALIAS" THINK="$THINK"
cd "$HERE"
echo "== stations =="; OUT=results/raw/flightbench-results.jsonl python benches/stations.py | tail -3
echo "== cryo ==";     OUT=results/raw/cryo-results.jsonl     python benches/cryo.py | tail -2
echo "== judgment =="; OUT=results/raw/v4-results.jsonl       python benches/judgment.py | tail -3
echo "== codegen ==";  OUT=results/raw/v5-results.jsonl       python benches/codegen.py | tail -2
python scripts/perf_from_log.py "results/logs/$ALIAS.log" "$ALIAS"
echo "== $ALIAS complete; add the lines above to results/RESULTS.md =="
