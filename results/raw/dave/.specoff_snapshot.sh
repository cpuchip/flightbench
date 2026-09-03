#!/bin/bash
# The whale's own condition, fresh: the CPU offload KV connector + a pool small enough that a side-load
# (churn.py) evicts the conversation's blocks between turns, so each turn reloads them from CPU.
# CPU region 2.4 GB (was 1.5): the host /dev/shm (23 GB) holds the production server's 20 GB region; a second 8 GB region cannot be backed (madvise EFAULT).
# Card 1, one container at a time. Pinned arms run MAX_LEN 32768 (the pinned budget must cover one request);
# KVB=0 means no pin: the whale's own pool (~252k tokens) and MAX_LEN, the whale's exact configuration minus its age.
# Tiers: int4 (alternative.sh), bf16 and int8 (start_qwen.sh CTX=fast/long).
until grep -q "OFFLOAD ARMS DONE" results/raw/dave/offload_arms.out 2>/dev/null; do sleep 20; done
OLD=sha256:9b7cfb685424c1f80b8588d98614a11eda9579174e70af0b69f12337b6f84f6b
NEW=sha256:9105b0f90fdddba53080303a63513c066cd60e396dd8f5fabd8ccb6bb0f7d9f1
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; TK=kv-probe-key
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/dave"; export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
CONN='--kv-transfer-config {"kv_connector":"OffloadingConnector","kv_role":"kv_both","kv_connector_extra_config":{"cpu_bytes_to_use":2400000000}}'
boot () {  # name, image, launcher, kv-bytes (0 = no pin), extra -e args...
  NAME=$1; IMG=$2; LAUNCH=$3; KVB=$4; shift 4; docker rm -f "$NAME" >/dev/null 2>&1
  if [ "$KVB" != 0 ]; then EXTRA="$CONN --kv-cache-memory-bytes $KVB"; ML=32768; else EXTRA="$CONN"; ML=244224; fi
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=$ML \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=long -e SPEC=dflash2 -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e VLLM_INT4_MQ_3D=1 -e MAX_SEQS=4 -e GPU_UTIL=0.93 \
    -e EXTRA_ARGS="$EXTRA" \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/$LAUNCH" >/dev/null || { echo "!!! $NAME docker run failed"; return 1; }
  for i in $(seq 1 90); do
    docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "!!! $NAME exited during boot"; docker logs "$NAME" 2>&1 | grep -iE "error|Traceback" | tail -6 | cut -c1-200; return 1; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { echo "[$NAME] SERVING at ~$((i*10))s: $(docker logs "$NAME" 2>&1 | grep -o 'GPU KV cache size: [0-9,]* tokens' | head -1) | connector: $(docker logs "$NAME" 2>&1 | grep -c OffloadingConnector) | kv dtype: $(docker logs "$NAME" 2>&1 | grep -oE "kv_cache_dtype[=: ]+'?[a-z0-9_]+" | head -1)"; return 0; }
    sleep 10
  done
  echo "!!! $NAME health timeout"; docker logs "$NAME" 2>&1 | tail -8 | cut -c1-200; return 1
}
loads () { curl -s -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/metrics | grep -E '^vllm:kv_offload_size_count.*CPU_to_GPU' | grep -oE '[0-9.]+$'; }
arm () {  # name, label, runs, churn-words, image, launcher, kv-bytes, then extra boot args
  NAME=$1; LABEL=$2; RUNS=$3; WORDS=$4; shift 4
  echo "########## $(date -u +%H:%M:%SZ) ARM $NAME ##########"
  boot "$NAME" "$@" || { docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; return 1; }
  rm -f "$OUTD/.churn-stop-$NAME"; python "$OUTD/churn.py" "$WORDS" 3 "$OUTD/.churn-stop-$NAME" > "$OUTD/churn-$NAME.log" 2>&1 &
  CH=$!
  for n in $(seq 1 $RUNS); do
    L0=$(loads)
    MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller PAD_TOKENS=${PAD:-4000} OUT="$OUTD/mission-matrix.jsonl" LABEL="$LABEL" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260
    echo "[$NAME] CPU->GPU load batches during run $n: $L0 -> $(loads)"
  done
  touch "$OUTD/.churn-stop-$NAME"; wait $CH 2>/dev/null; tail -1 "$OUTD/churn-$NAME.log"
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "[$NAME] torn down $(date -u +%H:%M:%SZ)"
}
# Sizing for reloads: GPU pool (pages) <= CPU region (pages), and mission + one churn prompt > GPU pool,
# so the conversation's pages leave the GPU between turns and are still on the CPU when the next turn asks.
# int4: 1.6 GB pool ~ 20 packed pages of 1,696 tokens; CPU 2.4 GB ~ 35 pages; mission ~11 pages + churn ~13.
# start_qwen.sh with SPEC=dflash2 takes its length from DFLASH_MAX_LEN, not MAX_LEN; bf16 costs ~79 KiB/token here
# (a 1,696-token page ~ 130 MB), so the bf16 and int8 arms run shorter conversations (PAD 0) and smaller churn prompts.

# Speculative decoding off (alternative.sh SPEC=off): is the drafter load-bearing for the crash? (review item 1)
arm off_specoff int4-specoff-offload 2 21000 "$OLD" alternative.sh 1600000000 -e SPEC=off
echo "SPECOFF ARM DONE $(date -u +%H:%M:%SZ)"