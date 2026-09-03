#!/bin/bash
# The connector arm per KV tier on the 0.28 port: OffloadingConnector + a pool pinned near the working set + a side-load
# that forces reloads between turns (the 0.27.1 engine-death recipe). One mission run per tier, two lanes.
until grep -q "TIER TABLE DONE" results/raw/v028/tier_table.out 2>/dev/null; do sleep 30; done
IMG=qwen38-27b-rtx3090:pr43-0.28
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CONN='--kv-transfer-config {"kv_connector":"OffloadingConnector","kv_role":"kv_both","kv_connector_extra_config":{"cpu_bytes_to_use":2400000000}}'
arm () {  # lane name label launcher ctx spec kv-bytes maxlen pad churn-words [extra -e ...]
  LANE=$1; NAME=$2; LABEL=$3; LAUNCH=$4; CTX=$5; SPEC=$6; KVB=$7; ML=$8; PAD=$9; WORDS=${10}; shift 10
  if [ "$LANE" = 0 ]; then CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020; else CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; fi
  export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=$ML -e DFLASH_MAX_LEN=$ML \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=$CTX -e SPEC=$SPEC -e PREFIX_CACHE=1 -e GPU_UTIL=0.93 -e MAX_SEQS=4 \
    -e EXTRA_ARGS="$CONN --kv-cache-memory-bytes $KVB" \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/$LAUNCH" >/dev/null || { echo "ARM $NAME: docker run failed"; return; }
  ok=0; for i in $(seq 1 90); do docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "ARM $NAME: exited during boot: $(docker logs "$NAME" 2>&1 | grep -E 'ValueError|Error:' | tail -1 | cut -c1-160)"; break; }; [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { ok=1; break; }; sleep 10; done
  if [ $ok = 1 ]; then
    echo "ARM $NAME serving: $(docker logs "$NAME" 2>&1 | grep -oE 'GPU KV cache size: [0-9,]+ tokens' | head -1) | connector: $(docker logs "$NAME" 2>&1 | grep -c OffloadingConnector)"
    rm -f "$OUTD/.churn-stop-$NAME"; python results/raw/dave/churn.py "$WORDS" 3 "$OUTD/.churn-stop-$NAME" > "$OUTD/churn-$NAME.log" 2>&1 & CH=$!
    L0=$(curl -s -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/metrics | grep -E '^vllm:kv_offload_size_count.*CPU_to_GPU' | grep -oE '[0-9.]+$')
    MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller PAD_TOKENS=$PAD OUT="$OUTD/mission-v028-connector.jsonl" LABEL="$LABEL" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260
    L1=$(curl -s -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/metrics | grep -E '^vllm:kv_offload_size_count.*CPU_to_GPU' | grep -oE '[0-9.]+$')
    echo "ARM $NAME CPU->GPU load batches: $L0 -> $L1 | engine alive: $(docker ps --format '{{.Names}}' | grep -c "^$NAME$") | fatal: $(docker logs "$NAME" 2>&1 | grep -c 'fatal error')"
    touch "$OUTD/.churn-stop-$NAME"; wait $CH 2>/dev/null
  fi
  ID=$(docker logs "$NAME" 2>&1 | grep -oE "vllm_offload_[0-9a-f-]+\.mmap" | head -1)
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1
  [ -n "$ID" ] && MSYS_NO_PATHCONV=1 docker run --rm --ipc host --entrypoint bash "$IMG" -c "rm -f /dev/shm/$ID && echo swept $ID" 2>/dev/null
  echo "ARM $NAME torn down $(date -u +%H:%M:%SZ)"
}
# pins: int4 1.6e9 (~35k tok), int8 2.2e9 @26k, bf16 2.5e9 @18k (pad 0, 10k churn), KVarN mtp 1.6e9 @32k
lane0 () { arm 0 c_int4 v028-int4-connector alternative.sh long dflash2 1600000000 32768 4000 21000 -e VLLM_INT4_MQ_3D=1; arm 0 c_bf16 v028-bf16-connector start_qwen.sh fast dflash2 2500000000 18000 0 10000; }
lane1 () { arm 1 c_int8 v028-int8-connector start_qwen.sh long dflash2 2200000000 26000 0 12000; arm 1 c_kvarn_mtp v028-kvarn-mtp-connector start_qwen.sh huge mtp 1600000000 32768 4000 21000; }
lane0 > "$OUTD/connector_arms.lane0.out" 2>&1 &
lane1 > "$OUTD/connector_arms.lane1.out" 2>&1 &
wait; cat "$OUTD/connector_arms.lane0.out" "$OUTD/connector_arms.lane1.out"; echo "CONNECTOR ARMS DONE $(date -u +%H:%M:%SZ)"
