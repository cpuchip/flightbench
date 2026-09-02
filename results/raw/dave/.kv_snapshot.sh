#!/bin/bash
# vLLM KV-cache tiers through judgment (v4) and mission v6.1: bf16 (CTX=fast), int8 per-token-head (CTX=long),
# KVarN k4v2 (CTX=huge), thinking off and on; same weights, draft, image and speculation as the whale; card 1 by UUID.
IMG=sha256:9b7cfb685424c1f80b8588d98614a11eda9579174e70af0b69f12337b6f84f6b   # the whale's image (ff41191)
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; TK=kv-probe-key
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/dave"; export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
boot () {  # tier, pre-command
  NAME="kv_$1"; docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound \
    -e CTX=$1 -e SPEC=dflash2 -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e VLLM_INT4_MQ_3D=1 -e MAX_SEQS=4 -e GPU_UTIL=0.93 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 \
    --entrypoint bash "$IMG" -c "${2}cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/start_qwen.sh" >/dev/null || { echo "!!! $NAME: docker run failed"; return 1; }
  for i in $(seq 1 90); do
    docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "!!! $NAME exited during boot"; docker logs "$NAME" 2>&1 | tail -12 | cut -c1-200; return 1; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { echo "[$NAME] SERVING at ~$((i*10))s: $(docker logs "$NAME" 2>&1 | grep -o 'GPU KV cache size: [0-9,]* tokens' | head -1) | $(docker logs "$NAME" 2>&1 | grep -o 'kv_cache_dtype[^,]*' | head -1)"; return 0; }
    sleep 10
  done
  echo "!!! $NAME: health timeout"; docker logs "$NAME" 2>&1 | tail -8 | cut -c1-200; return 1
}
run_tier () {  # tier, pre
  boot "$1" "$2" || { docker logs "kv_$1" > "$OUTD/server-kv_$1.log" 2>&1; docker rm -f "kv_$1" >/dev/null 2>&1; return 1; }
  M="qwen3.8-27b"; L="qwen3.8-27b-kv-$1"     # MODEL = the served name; LABEL = the row
  for T in off on; do MODEL="$M" LABEL="$L" THINK=$T OUT="$OUTD/judgment-vllm-kv.jsonl" timeout 900 python benches/judgment.py 2>&1 | grep -E "=== V4|Traceback|Error" | cut -c1-200; done
  for T in off on; do for n in 1 2; do MODEL="$M" LABEL="$L" THINK=$T MAXTOK=$([ "$T" = on ] && echo 6000 || echo 900) SEAT=controller OUT="$OUTD/mission-vllm-kv.jsonl" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260; done; done
  docker logs "kv_$1" > "$OUTD/server-kv_$1.log" 2>&1; docker rm -f "kv_$1" >/dev/null 2>&1; echo "[kv_$1] torn down $(date -u +%H:%M:%SZ)"
}
echo "########## $(date -u +%H:%M:%SZ) TIER fast (bf16 KV) ##########"; run_tier fast ""
echo "########## $(date -u +%H:%M:%SZ) TIER long (int8 per-token-head KV) ##########"; run_tier long ""
echo "########## $(date -u +%H:%M:%SZ) TIER huge (KVarN k4v2) ##########"; run_tier huge "cd /app && bash kvarn/install.sh > /tmp/kvarn-install.log 2>&1 && "
echo "VLLM KV SERIES DONE $(date -u +%H:%M:%SZ)"
