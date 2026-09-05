#!/bin/bash
# Flightbench at the model's recommended sampling, enough seeds to mean something, on BOTH engine
# versions. Three seeds gave 17/16/10 against a greedy 18/18/18; ten seeds per image decides
# whether recommended becomes the bench default, and the 0.27.1 image answers a question the
# whole greedy-era investigation never asked: does the version difference exist at real
# sampling at all? The merged image gets the draft_sample_method field, i.e. what production
# runs now. One greedy run per image as the replay anchor. Card 1.
set -u
LOCK=/tmp/fb_seeds.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025
VOL=qwen-cache-lane1
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
image () {  # tag image apply_field(0|1)
  TAG=$1; IMG=$2; APPLY=$3; NAME="fb-$TAG"
  if [ "$APPLY" = 1 ]; then PRE="$FIELD"; else PRE=""; fi
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=57344 -e DFLASH_MAX_LEN=57344 \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=fast -e SPEC=dflash2 -e DFLASH_TOKENS=15 -e PREFIX_CACHE=1 \
    -e GPU_UTIL=0.90 -e MAX_SEQS=4 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 \
    --entrypoint bash "$IMG" -c "$PRE"'cd /app && echo "$VLLM_API_KEY" > api_key.txt && exec bash single-user/start_qwen.sh' >/dev/null \
    || { echo "FB $TAG: docker run failed"; return; }
  ok=0
  for i in $(seq 1 180); do
    docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "FB $TAG: exited during boot"; docker logs "$NAME" 2>&1 | tail -5; break; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] \
      && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { ok=1; break; }
    sleep 10
  done
  [ $ok = 1 ] || { echo "FB $TAG: no health"; docker rm -f "$NAME" >/dev/null 2>&1; return; }
  echo "FB $TAG serving: $(docker logs "$NAME" 2>&1 | grep -oE 'draft_logits=(True|False)' | head -1)"
  run () {  # label temp top_p top_k seed
    L=$1; T=$2; P=$3; K=$4; S=$5
    ENVV="MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller OUT=$OUTD/mission-fb-seeds.jsonl LABEL=$L TEMPERATURE=$T SEED=$S"
    [ -n "$P" ] && ENVV="$ENVV TOP_P=$P"; [ -n "$K" ] && ENVV="$ENVV TOP_K=$K"
    env $ENVV timeout 2400 python benches/mission.py > "$OUTD/mission-$L.log" 2>&1 || { echo "FB $L: RUN FAILED"; tail -3 "$OUTD/mission-$L.log"; }
    python - "$L" "$OUTD/mission-fb-seeds.jsonl" <<'PY'
import json, sys
sys.stdout.reconfigure(encoding="utf-8")
lab, path = sys.argv[1], sys.argv[2]
rec = None
for line in open(path, encoding="utf-8"):
    try: o = json.loads(line)
    except Exception: continue
    if o.get("model") == lab and o.get("decisions"): rec = o
if not rec: print(f"FB {lab}: NO RECORD"); sys.exit()
d = rec["decisions"]; bad = [k for k, v in d.items() if not v]
print(f"FB {lab}: {sum(1 for v in d.values() if v)}/{len(d)} failed={','.join(bad) if bad else '-'}")
PY
  }
  run "greedy-$TAG" 0 "" "" 1
  for S in 1 2 3 4 5 6 7 8 9 10; do run "rec-$TAG-s$S" 1.0 0.95 20 "$S"; done
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1
  echo "FB $TAG done $(date -u +%H:%M:%SZ)"
}
image merged qwen38-27b-rtx3090:pr43-6869c80 1
image v0271  qwen38-27b-rtx3090:main-8d832f8  0
echo "FB SEEDS DONE $(date -u +%H:%M:%SZ)"
