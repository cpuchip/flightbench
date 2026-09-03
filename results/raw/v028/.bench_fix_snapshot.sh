#!/bin/bash
# The A/B measures the heads as filed, so the port KVarN + DFlash2 row is the broken geometry. Measure that tier on the fix branch too.
until grep -q "BENCH INT4 RERUN DONE" results/raw/v028/bench_int4_rerun.out 2>/dev/null; do sleep 30; done
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
bcell () {  # lane version image name launcher ctx spec [extra -e ...]
  LANE=$1; VER=$2; IMG=$3; NAME=b_${VER}_$4; LAUNCH=$5; CTX=$6; SPEC=$7; shift 7
  if [ "$LANE" = 0 ]; then CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020; else CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; fi
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=$CTX -e SPEC=$SPEC -e PREFIX_CACHE=1 -e GPU_UTIL=0.93 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/$LAUNCH" >/dev/null || { echo "BENCH $NAME: docker run failed"; return; }
  ok=0; for i in $(seq 1 90); do docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "BENCH $NAME: exited during boot"; break; }; [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { ok=1; break; }; sleep 10; done
  if [ $ok = 1 ]; then
    echo "BENCH $NAME ($VER $LAUNCH CTX=$CTX SPEC=$SPEC) serving: $(docker logs "$NAME" 2>&1 | grep -oE 'GPU KV cache size: [0-9,]+ tokens' | head -1)"
    docker exec -e HOST=127.0.0.1 -e PORT=$PORT -e VLLM_API_KEY=$TK -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound "$NAME" bash -c "cd /app && timeout 1500 bash bench/run_benchmarks.sh single" 2>&1 | grep -E "^ROW|^#|error|Error" | sed "s/^/BENCH $NAME /" | cut -c1-230
  fi
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "BENCH $NAME torn down $(date -u +%H:%M:%SZ)"
}
FIX=qwen38-27b-rtx3090:pr43-swpad
bcell 0 fix $FIX huge_dflash2 start_qwen.sh huge dflash2 > "$OUTD/bench_fix.lane0.out" 2>&1 &
bcell 1 fix $FIX huge_mtp start_qwen.sh huge mtp > "$OUTD/bench_fix.lane1.out" 2>&1 &
wait; cat "$OUTD/bench_fix.lane0.out" "$OUTD/bench_fix.lane1.out"; echo "BENCH FIX DONE $(date -u +%H:%M:%SZ)"
