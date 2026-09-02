#!/bin/bash
# The int4 per-token-head tier with the multi-query 3D path OFF (VLLM_INT4_MQ_3D=0): the whale's exact
# launcher (alternative.sh), image, weights, draft and speculation, on card 1; judgment off/on, mission x2 per mode.
IMG=sha256:9b7cfb685424c1f80b8588d98614a11eda9579174e70af0b69f12337b6f84f6b
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; TK=kv-probe-key
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/dave"; export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
NAME=kv_int4_2d; docker rm -f "$NAME" >/dev/null 2>&1
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
  -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
  -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=244224 \
  -e CTX=long -e SPEC=dflash2 -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e VLLM_INT4_MQ_3D=0 -e MAX_SEQS=4 -e GPU_UTIL=0.93 \
  -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 \
  --entrypoint bash "$IMG" -c "cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/alternative.sh" >/dev/null || { echo "!!! docker run failed"; exit 1; }
for i in $(seq 1 90); do
  docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "!!! $NAME exited during boot"; docker logs "$NAME" 2>&1 | tail -12 | cut -c1-200; exit 1; }
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { echo "[$NAME] SERVING at ~$((i*10))s: $(docker logs "$NAME" 2>&1 | grep -o 'GPU KV cache size: [0-9,]* tokens' | head -1) | $(docker logs "$NAME" 2>&1 | grep -o 'kv_cache_dtype[^,]*' | head -1) | 3D lines: $(docker logs "$NAME" 2>&1 | grep -c 'int4 3D')"; break; }
  [ $i = 90 ] && { echo "!!! health timeout"; docker logs "$NAME" 2>&1 | tail -8 | cut -c1-200; exit 1; }
  sleep 10
done
M="qwen3.8-27b"; L="qwen3.8-27b-int4-2d"
for T in off on; do MODEL="$M" LABEL="$L" THINK=$T OUT="$OUTD/judgment-vllm-kv.jsonl" timeout 900 python benches/judgment.py 2>&1 | grep -E "=== V4|Traceback|Error" | cut -c1-200; done
for T in off on; do for n in 1 2; do MODEL="$M" LABEL="$L" THINK=$T MAXTOK=$([ "$T" = on ] && echo 6000 || echo 900) SEAT=controller OUT="$OUTD/mission-vllm-kv.jsonl" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260; done; done
docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "[$NAME] torn down $(date -u +%H:%M:%SZ)"; echo "INT4-2D ARM DONE"
