#!/bin/bash
# DFLASH_TOKENS=15 on the int4 tier (fork main dfee877, #63 fixed, so depth > 7 boots): the 9..16 query-token
# band the 3D scratch sizing was written for. Arms: 3D on (DEBUG census), 3D off, 3D on + Patch B at boot.
IMG=qwen38-27b-rtx3090:dfee877
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; TK=kv-probe-key
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
PB='C:\Users\cpuch\Documents\code\stuffleberry\workspace\private-workspace\.spec\bench\patchb\spec-decode-scratch-within-budget.patch'
OUTD="results/raw/dave"; export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
boot () {  # name, patch-or-none, extra -e args...
  NAME=$1; PATCH=$2; shift 2; docker rm -f "$NAME" >/dev/null 2>&1
  if [ "$PATCH" != none ]; then PV=(-v "$PATCH:/tmp/pb.patch:ro"); CMD='cd /app/venv/lib/python3.12/site-packages/vllm && { patch -p1 -N < /tmp/pb.patch || { echo PATCH-FAILED; exit 97; }; } && cd /app && echo "$VLLM_API_KEY" > api_key.txt && exec bash single-user/alternative.sh'; else PV=(); CMD='cd /app && echo "$VLLM_API_KEY" > api_key.txt && exec bash single-user/alternative.sh'; fi
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models "${PV[@]}" \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=32768 \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=long -e SPEC=dflash2 -e DFLASH_TOKENS=15 -e PREFIX_CACHE=1 -e VLLM_INT4_MQ_3D=1 -e VLLM_INT4_MQ_3D_DEBUG=1 -e MAX_SEQS=4 -e GPU_UTIL=0.93 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "$CMD" >/dev/null || { echo "!!! $NAME docker run failed"; return 1; }
  for i in $(seq 1 90); do
    docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "!!! $NAME exited during boot"; docker logs "$NAME" 2>&1 | grep -iE "PATCH-FAILED|Hunk|error|Traceback" | tail -6 | cut -c1-200; return 1; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { echo "[$NAME] SERVING at ~$((i*10))s: $(docker logs "$NAME" 2>&1 | grep -o 'GPU KV cache size: [0-9,]* tokens' | head -1) | scratch lines: $(docker logs "$NAME" 2>&1 | grep -c 'int4 3D scratch') | $(docker logs "$NAME" 2>&1 | grep -oE 'int4 3D scratch: capacity=[0-9]+ query tokens[^;]*' | head -1)"; return 0; }
    sleep 10
  done
  echo "!!! $NAME health timeout"; return 1
}
census () {  # dispatch census from the DEBUG lines
  docker logs "$1" 2>&1 | grep -oE "\[int4-mq3d\] tokens=[0-9]+ num_seqs=[0-9]+ max_seqlen_q=[0-9]+ use_3d=(True|False)" | sed -E 's/tokens=[0-9]+ //' | sort | uniq -c | sort -rn | head -12 | awk '{printf "    %s x%d\n", $2" "$3" "$4, $1}'
  echo "    breach/degraded lines: $(docker logs "$1" 2>&1 | grep -ciE 'DEGRADED|breach')"
}
arm () {  # name, label, runs, patch, extra boot args
  NAME=$1; LABEL=$2; RUNS=$3; PATCH=$4; shift 4
  echo "########## $(date -u +%H:%M:%SZ) ARM $NAME ##########"
  boot "$NAME" "$PATCH" "$@" || { docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; return 1; }
  MODEL=qwen3.8-27b THINK=off OUT="$OUTD/judgment-k15.jsonl" LABEL="$LABEL" timeout 900 python benches/judgment.py 2>&1 | grep -E "=== V4|Traceback|Error" | cut -c1-200
  for n in $(seq 1 $RUNS); do MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller OUT="$OUTD/mission-k15.jsonl" LABEL="$LABEL" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260; done
  echo "[$NAME] dispatch census (max_seqlen_q, use_3d):"; census "$NAME"
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "[$NAME] torn down $(date -u +%H:%M:%SZ)"
}
arm k15_3d     int4-k15-3d      2 none
arm k15_2d     int4-k15-2d      2 none -e VLLM_INT4_MQ_3D=0
arm k15_patchb int4-k15-3d-patchb 1 "$PB"
echo "K15 ARMS DONE $(date -u +%H:%M:%SZ)"
