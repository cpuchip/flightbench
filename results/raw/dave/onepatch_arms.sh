#!/bin/bash
# One patch at a time on the production image (ff41191), 3D on: which of the patches between the images stops the collapse.
until grep -q "PATCHA ARM DONE" results/raw/dave/patcha_arm.out 2>/dev/null; do sleep 20; done
OLD=sha256:9b7cfb685424c1f80b8588d98614a11eda9579174e70af0b69f12337b6f84f6b
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; TK=kv-probe-key
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
PD="C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/qwen38-27b-rtx3090/patches"
OUTD="results/raw/dave"; export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
for P in mamba-align-checkpoint-order spec-sampler-prewarm; do
  NAME="mx_p_$P"; docker rm -f "$NAME" >/dev/null 2>&1
  echo "########## $(date -u +%H:%M:%SZ) ARM $NAME ##########"
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models -v "$PD/$P.patch:/tmp/a.patch:ro" \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=244224 \
    -e CTX=long -e SPEC=dflash2 -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e VLLM_INT4_MQ_3D=1 -e MAX_SEQS=4 -e GPU_UTIL=0.93 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 \
    --entrypoint bash "$OLD" -c "cd /app/venv/lib/python3.12/site-packages/vllm && { patch -p1 -N < /tmp/a.patch || { echo PATCH-FAILED; exit 97; }; } && cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/alternative.sh" >/dev/null || { echo "!!! docker run failed"; continue; }
  ok=0
  for i in $(seq 1 90); do
    docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "!!! $NAME exited during boot (patch apply?)"; docker logs "$NAME" 2>&1 | grep -E 'PATCH-FAILED|Hunk|FAILED|rror' | head -6 | cut -c1-160; break; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { echo "[$NAME] SERVING at ~$((i*10))s"; ok=1; break; }
    sleep 10
  done
  if [ $ok = 1 ]; then MODEL=qwen3.8-27b LABEL="int4-3d-oldimage-$P" THINK=off MAXTOK=900 SEAT=controller OUT="$OUTD/mission-matrix.jsonl" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260; fi
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "[$NAME] torn down $(date -u +%H:%M:%SZ)"
done
echo "ONEPATCH ARMS DONE $(date -u +%H:%M:%SZ)"
