#!/bin/bash
# One cohort arm against the running test container: the record's client (perpos_client.py, 8 real
# prompts x the given seeds, 1024 tokens, counters read per prompt from /tmp/server.log inside).
# usage: run-arm.sh <ARM> <SEEDS>   e.g. run-arm.sh main-a1 1,2,3,4
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=${NAME:-qwen-main-test}; PORT=${PORT:-18021}
ARM=$1; SEEDS=$2
OUT="$HERE/cohort-$ARM.txt"
# The client rides in as base64 through the exec environment (the record's harness did the same):
# docker cp from Git Bash mangles one side of the path whichever way MSYS conversion is set.
SWEEP_B64="$(base64 -w0 "$HERE/perpos_client.py")"
echo "ARM $ARM seeds=$SEEDS start $(date -u +%H:%M:%SZ)" | tee "$OUT"
docker exec -e PORT=$PORT -e ARM="$ARM" -e SEEDS="$SEEDS" -e SWEEP_B64="$SWEEP_B64" --env-file "$(cygpath -w "$HERE/maintest.env")" "$NAME" \
  bash -c 'echo "$SWEEP_B64" | base64 -d > /tmp/sweep_client.py; grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1; grep -oE "GPU KV cache size: [0-9,]+ tokens" /tmp/server.log | head -1; cd /app && /app/venv/bin/python /tmp/sweep_client.py' 2>&1 | tee -a "$OUT"
echo "ARM $ARM end $(date -u +%H:%M:%SZ) rows=$(grep -c '^ROW ' "$OUT")" | tee -a "$OUT"
