#!/bin/bash
# The 3D-collapse control matrix, card 1, one container at a time, int4 per-token-head with the 3D verify path ON:
#  a) the CURRENT image (post-#57), DEBUG dispatch on          -> does the collapse survive the scratch fix?
#  b) production image, PREFIX_CACHE=0                          -> is prefix caching in it?
#  c) production image, DFLASH_TOKENS=3                         -> does the verify batch width matter?
#  d) production image, PAD_TOKENS=4000 and 8000 (one run each) -> does onset track length or the conversation?
OLD=sha256:9b7cfb685424c1f80b8588d98614a11eda9579174e70af0b69f12337b6f84f6b   # ff41191, the production image
NEW=sha256:9105b0f90fdddba53080303a63513c066cd60e396dd8f5fabd8ccb6bb0f7d9f1   # 2bbd292, current (post-#57)
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; TK=kv-probe-key
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/dave"; export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
boot () {  # name, image, extra -e args...
  NAME=$1; IMG=$2; shift 2; docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=244224 \
    -e CTX=long -e SPEC=dflash2 -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e VLLM_INT4_MQ_3D=1 -e MAX_SEQS=4 -e GPU_UTIL=0.93 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/alternative.sh" >/dev/null || { echo "!!! $NAME docker run failed"; return 1; }
  for i in $(seq 1 90); do
    docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "!!! $NAME exited during boot"; docker logs "$NAME" 2>&1 | tail -12 | cut -c1-200; return 1; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { echo "[$NAME] SERVING at ~$((i*10))s: $(docker logs "$NAME" 2>&1 | grep -o 'GPU KV cache size: [0-9,]* tokens' | head -1) | 3D lines: $(docker logs "$NAME" 2>&1 | grep -c 'int4 3D')"; return 0; }
    sleep 10
  done
  echo "!!! $NAME health timeout"; docker logs "$NAME" 2>&1 | tail -8 | cut -c1-200; return 1
}
arm () {  # name, label, runs, extra env for the bench (as VAR=val words), then boot args after --
  NAME=$1; LABEL=$2; RUNS=$3; shift 3; BENV=(); while [ "$1" != "--" ]; do BENV+=("$1"); shift; done; shift
  echo "########## $(date -u +%H:%M:%SZ) ARM $NAME ##########"
  boot "$NAME" "$@" || { docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; return 1; }
  MODEL=qwen3.8-27b THINK=off OUT="$OUTD/judgment-matrix.jsonl" LABEL="$LABEL" env "${BENV[@]}" timeout 900 python benches/judgment.py 2>&1 | grep -E "=== V4|Traceback|Error" | cut -c1-200
  for n in $(seq 1 $RUNS); do MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller OUT="$OUTD/mission-matrix.jsonl" LABEL="$LABEL" env "${BENV[@]}" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260; done
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "[$NAME] torn down $(date -u +%H:%M:%SZ)"
}
arm mx_newimg   int4-3d-newimage  2 -- "$NEW" -e VLLM_INT4_MQ_3D_DEBUG=1
arm mx_noprefix int4-3d-noprefix  2 -- "$OLD" -e PREFIX_CACHE=0
arm mx_k3       int4-3d-k3        2 -- "$OLD" -e DFLASH_TOKENS=3
arm mx_pad4k    int4-3d-pad4k     1 PAD_TOKENS=4000 -- "$OLD"
arm mx_pad8k    int4-3d-pad8k     1 PAD_TOKENS=8000 -- "$OLD"
echo "MQ3D MATRIX DONE $(date -u +%H:%M:%SZ)"
