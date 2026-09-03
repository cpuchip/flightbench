#!/bin/bash
# 0.28 port validation, the maintainer's boot matrix: start_qwen.sh {fast,long,huge} x {mtp,dflash2,off} + alternative.sh int4 x {dflash2,off}.
# Two lanes (card 0 / card 1), one container per lane at a time. Per cell: boot, pool, warnings of note, the exact-output probe.
IMG=qwen38-27b-rtx3090:pr43-0.28
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
cell () {  # lane(0|1) name launcher ctx spec [extra -e ...]
  LANE=$1; NAME=$2; LAUNCH=$3; CTX=$4; SPEC=$5; shift 5
  if [ "$LANE" = 0 ]; then CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020; else CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; fi
  docker rm -f "$NAME" >/dev/null 2>&1; T0=$(date +%s)
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=$CTX -e SPEC=$SPEC -e PREFIX_CACHE=1 -e GPU_UTIL=0.93 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/$LAUNCH" >/dev/null || { echo "CELL $NAME: docker run failed"; return; }
  R="boot-timeout"
  for i in $(seq 1 90); do
    docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { R="EXITED: $(docker logs "$NAME" 2>&1 | grep -E 'Error|error:|assert' | grep -v 'Engine core initialization' | tail -1 | cut -c1-160)"; break; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { R="SERVING $(( $(date +%s) - T0 ))s"; break; }
    sleep 10
  done
  if [[ "$R" == SERVING* ]]; then
    POOL=$(docker logs "$NAME" 2>&1 | grep -oE 'GPU KV cache size: [0-9,]+ tokens' | head -1 | grep -oE '[0-9,]+ tokens')
    PROBE=$(BASE=http://127.0.0.1:$PORT/v1 KEY=$TK python "$OUTD/probe_count.py" 2>&1 | tail -1)
    WARN=$(docker logs "$NAME" 2>&1 | grep -E "WARNING" | grep -vE "max_frames|min_frames|pin_memory|deprecat|generation_config|JIT|Unknown vLLM environment|rms_norm|max_num_scheduled|mamba_ssm_dtype" | sed -E 's/^\([A-Za-z_0-9]+ pid=[0-9]+\) WARNING [0-9-]+ [0-9:]+ //' | cut -c1-110 | sort -u | head -3 | tr '\n' ';')
    echo "CELL $NAME | $LAUNCH CTX=$CTX SPEC=$SPEC | $R | pool $POOL | probe $PROBE | warn: $WARN"
  else
    echo "CELL $NAME | $LAUNCH CTX=$CTX SPEC=$SPEC | $R"
  fi
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1
}
# bf16 (fast) at the launcher's 65,536 default needs 4.76 GiB; this WSL2 card has 4.71 at GPU_UTIL 0.93, so fast runs at the launcher's own 57,344 alternate here
lane0 () { F=(-e MAX_LEN=57344 -e DFLASH_MAX_LEN=57344); cell 0 m_fast_mtp start_qwen.sh fast mtp "${F[@]}"; cell 0 m_fast_dflash2 start_qwen.sh fast dflash2 "${F[@]}"; cell 0 m_fast_off start_qwen.sh fast off "${F[@]}"; cell 0 m_huge_mtp start_qwen.sh huge mtp; cell 0 m_huge_dflash2 start_qwen.sh huge dflash2; cell 0 m_huge_off start_qwen.sh huge off; }
lane1 () { cell 1 m_long_mtp start_qwen.sh long mtp; cell 1 m_long_dflash2 start_qwen.sh long dflash2; cell 1 m_long_off start_qwen.sh long off; cell 1 m_int4_dflash2 alternative.sh long dflash2 -e VLLM_INT4_MQ_3D=1; cell 1 m_int4_off alternative.sh long off -e VLLM_INT4_MQ_3D=1; }
docker rm -f whale >/dev/null 2>&1 && echo "int4 server stopped"
lane0 > "$OUTD/boot_matrix.lane0.out" 2>&1 &
lane1 > "$OUTD/boot_matrix.lane1.out" 2>&1 &
wait
cat "$OUTD/boot_matrix.lane0.out" "$OUTD/boot_matrix.lane1.out"
echo "BOOT MATRIX DONE $(date -u +%H:%M:%SZ)"
