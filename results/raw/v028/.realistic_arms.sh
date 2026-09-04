#!/bin/bash
# Michael's question: our mission bench has always run greedy (temperature 0), but this model
# card recommends temperature 1.0, top_p 0.95, top_k 20. A greedy bench measures a regime the
# model is not shipped for -- and on a knife-edge model it also makes the score a function of
# which kernels the autotuner drew. Same server, one boot, both regimes, several seeds each.
set -u
LOCK=/tmp/realistic.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025
VOL=qwen-cache-lane1; IMG=qwen38-27b-rtx3090:pr43-6869c80
NAME=realistic
docker rm -f "$NAME" >/dev/null 2>&1
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
  -v "$VOL":/cache -v "$MODELS":/app/models \
  -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=57344 -e DFLASH_MAX_LEN=57344 \
  -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=fast -e SPEC=dflash2 -e DFLASH_TOKENS=15 -e PREFIX_CACHE=1 \
  -e GPU_UTIL=0.90 -e MAX_SEQS=4 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 \
  --entrypoint bash "$IMG" -c 'cd /app && echo "$VLLM_API_KEY" > api_key.txt && exec bash single-user/start_qwen.sh' >/dev/null \
  || { echo "docker run failed"; exit 1; }
ok=0
for i in $(seq 1 150); do
  docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "exited during boot"; docker logs "$NAME" 2>&1 | tail -5; break; }
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] \
    && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { ok=1; break; }
  sleep 10
done
[ $ok = 1 ] || { echo "REALISTIC: no health"; docker rm -f "$NAME" >/dev/null 2>&1; exit 1; }
export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
row () {  # label temp top_p top_k seed
  L=$1; T=$2; P=$3; K=$4; S=$5
  ENVV="MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller OUT=$OUTD/mission-realistic.jsonl LABEL=$L TEMPERATURE=$T"
  [ -n "$P" ] && ENVV="$ENVV TOP_P=$P"; [ -n "$K" ] && ENVV="$ENVV TOP_K=$K"; [ -n "$S" ] && ENVV="$ENVV SEED=$S"
  env $ENVV timeout 2400 python benches/mission.py > "$OUTD/mission-$L.log" 2>&1 || { echo "REALISTIC $L: RUN FAILED"; tail -4 "$OUTD/mission-$L.log"; }
  python - "$L" <<'PY'
import json, glob, os, sys
sys.stdout.reconfigure(encoding="utf-8")
lab = sys.argv[1]
fs = sorted(glob.glob(f"results/raw/v028/v6-{lab}-*trace.jsonl"), key=os.path.getmtime)
if not fs: print(f"REALISTIC {lab}: NO TRACE"); sys.exit()
rows = [json.loads(l) for l in open(fs[-1], encoding="utf-8")]
reps = [r for r in rows if r.get("kind") == "reply"]
calls = sum(1 for r in rows if r.get("kind") == "tool")
fin = [r.get("finish") for r in reps]
print(f"REALISTIC {lab}: calls {calls} capped {fin.count('max_iters')}/{len(reps)} length-cut {fin.count('length')}")
PY
}
for S in 1 2 3; do row "greedy-s$S"    0   ""    ""  "$S"; done
for S in 1 2 3; do row "recommended-s$S" 1.0 0.95 20  "$S"; done
docker logs "$NAME" > "$OUTD/server-realistic.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1
echo "REALISTIC ARMS DONE $(date -u +%H:%M:%SZ)"
