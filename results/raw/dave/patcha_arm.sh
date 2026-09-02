#!/bin/bash
# The production image (ff41191) with Patch A (spec-decode-scratch-token-units) applied at boot, 3D on: isolates
# Patch A from #48's sampler prewarm as the fix between the images. Waits for the matrix to release card 1.
until grep -q "MQ3D MATRIX DONE" results/raw/dave/mq3d_matrix.out 2>/dev/null; do sleep 20; done
OLD=sha256:9b7cfb685424c1f80b8588d98614a11eda9579174e70af0b69f12337b6f84f6b
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; TK=kv-probe-key
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
PATCH="C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/qwen38-27b-rtx3090/patches/spec-decode-scratch-token-units.patch"
OUTD="results/raw/dave"; export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK; NAME=mx_patcha
docker rm -f "$NAME" >/dev/null 2>&1
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
  -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models -v "$PATCH:/tmp/a.patch:ro" \
  -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=244224 \
  -e CTX=long -e SPEC=dflash2 -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e VLLM_INT4_MQ_3D=1 -e MAX_SEQS=4 -e GPU_UTIL=0.93 \
  -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 \
  --entrypoint bash "$OLD" -c "cd /app/venv/lib/python3.12/site-packages/vllm && { patch -p1 < /tmp/a.patch || { echo PATCH-FAILED; exit 97; }; } && cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/alternative.sh" >/dev/null || { echo "!!! docker run failed"; exit 1; }
for i in $(seq 1 90); do
  docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "!!! $NAME exited during boot"; docker logs "$NAME" 2>&1 | tail -12 | cut -c1-200; exit 1; }
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { echo "[$NAME] SERVING at ~$((i*10))s | scratch lines: $(docker logs "$NAME" 2>&1 | grep -c 'int4 3D scratch: capacity=')"; break; }
  [ $i = 90 ] && { echo "!!! health timeout"; exit 1; }; sleep 10
done
for n in 1 2; do MODEL=qwen3.8-27b LABEL=int4-3d-oldimage-patchA THINK=off MAXTOK=900 SEAT=controller OUT="$OUTD/mission-matrix.jsonl" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260; done
docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "PATCHA ARM DONE $(date -u +%H:%M:%SZ)"
