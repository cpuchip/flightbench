#!/bin/bash
# The flightbench tier table on the 0.28 port: judgment (v4) + mission (v6.1) x thinking off/on, per KV tier. Two lanes.
until grep -q "BOOT MATRIX DONE" results/raw/v028/boot_matrix.out 2>/dev/null; do sleep 30; done
IMG=qwen38-27b-rtx3090:pr43-0.28
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
tier () {  # lane name label launcher ctx spec [extra -e ...]
  LANE=$1; NAME=$2; LABEL=$3; LAUNCH=$4; CTX=$5; SPEC=$6; shift 6
  if [ "$LANE" = 0 ]; then CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020; else CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; fi
  export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=$CTX -e SPEC=$SPEC -e PREFIX_CACHE=1 -e GPU_UTIL=0.93 -e MAX_SEQS=4 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/$LAUNCH" >/dev/null || { echo "TIER $NAME: docker run failed"; return; }
  ok=0; for i in $(seq 1 90); do docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "TIER $NAME: exited during boot"; break; }; [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { ok=1; break; }; sleep 10; done
  if [ $ok = 1 ]; then
    echo "TIER $NAME serving: $(docker logs "$NAME" 2>&1 | grep -oE 'GPU KV cache size: [0-9,]+ tokens' | head -1)"
    for TH in off on; do
      CAP=900; [ $TH = on ] && CAP=6000
      MODEL=qwen3.8-27b THINK=$TH OUT="$OUTD/judgment-v028.jsonl" LABEL="$LABEL" timeout 1200 python benches/judgment.py 2>&1 | grep -E "=== V4|Traceback|Error" | cut -c1-200
      for n in 1 2; do MODEL=qwen3.8-27b THINK=$TH MAXTOK=$CAP SEAT=controller OUT="$OUTD/mission-v028.jsonl" LABEL="$LABEL" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260; done
    done
  fi
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "TIER $NAME torn down $(date -u +%H:%M:%SZ)"
}
lane0 () { tier 0 t_bf16 v028-bf16-dflash2 start_qwen.sh fast dflash2 -e MAX_LEN=57344 -e DFLASH_MAX_LEN=57344; tier 0 t_kvarn_mtp v028-kvarn-mtp start_qwen.sh huge mtp; tier 0 t_kvarn_dflash2 v028-kvarn-dflash2 start_qwen.sh huge dflash2; }
lane1 () { tier 1 t_int8 v028-int8-dflash2 start_qwen.sh long dflash2; tier 1 t_int4 v028-int4-dflash2 alternative.sh long dflash2 -e VLLM_INT4_MQ_3D=1; }
lane0 > "$OUTD/tier_table.lane0.out" 2>&1 &
lane1 > "$OUTD/tier_table.lane1.out" 2>&1 &
wait; cat "$OUTD/tier_table.lane0.out" "$OUTD/tier_table.lane1.out"; echo "TIER TABLE DONE $(date -u +%H:%M:%SZ)"
