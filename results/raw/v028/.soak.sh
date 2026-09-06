#!/bin/bash
# .soak.sh — the overnight soak at the shipped defaults (2026-09-06, Michael: "1 and 2 have merit").
# Card 0, SPEC=dflash2 CTX=fast, the launcher's own memory defaults (5.2 GiB pin, 65536, GPU_UTIL 0.90 as every
# chain used), lookup on, the fork's verify kernel on. The 32-request cohort (8 prompts x 4 seeds, the same seeds
# every pass) is run pass after pass for SOAK_HOURS; each pass is tagged ARM=soak-p<N> so per-pass step time,
# acceptance and any ROW_ERROR / SERVER_GONE can be read by pass. Fixed seeds make every pass a determinism check
# as well (at the default, nine boots were one trajectory; this asks whether one boot stays on it for hours).
# The adapter counters are sampled by soak-sampler.ps1 (started beside this script) into spill-counters-soak.txt,
# and the engine log is copied out of the container every five minutes (serverlog-soak.txt), so a fault leaves
# its line behind. Readings registered before the boot: no ROW_ERROR/SERVER_GONE, shared usage at baseline and
# step time flat across passes = the default holds for the night on this host; a fault or a drift = the pass,
# the step count and the counters at that minute are the reading.
set -u
export MSYS_NO_PATHCONV=1
OUTD=<workspace>/projects/flightbench/results/raw/v028
MODELS='<workspace>\projects\qwen38-27b-rtx3090\models'
IMG=qwen38-27b-rtx3090:pr43-6869c80
CARD=0; PORT=18020; VOL=qwen-cache-lane0; NAME=soak
SOAK_HOURS=${SOAK_HOURS:-7}
LOCK=/tmp/soak.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live soak $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"
TK=$(python -c "import secrets;print(secrets.token_hex(8))")
CLIENT_B64=$(base64 -w0 "$OUTD/perpos_client.py")
# the image's launcher predates the draft_sample_method field the shipped default sets; apply it in the container
FIELD_B64=$(base64 -w0 "$OUTD/field_patch.py")

# idle gate: card 0 under 500 MiB used, then 30 s of quiet
for i in $(seq 1 60); do
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i $CARD | tr -d ' ')
  [ "${used:-9999}" -lt 500 ] && break; sleep 10
done
sleep 30
echo "SOAK IDLE_GATE $(date -u +%H:%M:%SZ) card0_used=${used}MiB"

docker rm -f "$NAME" >/dev/null 2>&1
docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
  -v "$VOL":/cache -v "$MODELS":/app/models \
  -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT \
  -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 \
  -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
  -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
  -e SOAK_HOURS=$SOAK_HOURS -e FIELD_B64="$FIELD_B64" \
  --entrypoint bash "$IMG" -c '
    cd /app && echo "$VLLM_API_KEY" > api_key.txt && export PATH=/app/venv/bin:$PATH
    echo "$FIELD_B64" | base64 -d | python -
    echo "SPEC_CFG_LINE $(grep -n "method.*dflash.*num_speculative_tokens" single-user/start_qwen.sh | head -1 | cut -c1-200)"
    nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
    for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
    curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; grep -n -m1 -B3 -A30 -iE "Traceback|Error" /tmp/server.log | cut -c1-240 | head -60; exit 1; }
    echo "SOAK HEALTH $(date -u +%H:%M:%SZ)"
    echo "RESOLVED $(grep -oE "max_model_len.: [0-9]+" /tmp/server.log | head -1) $(grep -oE "kv_cache_memory_bytes.: [0-9]+" /tmp/server.log | head -1)"
    echo "SEQUENCE $(grep -oE "Directly load AOT compilation|Compiling a graph for compile range|Using cache directory: [^ ]*rank_0_0/[a-z0-9_]+" /tmp/server.log | sed -E "s|Directly load AOT compilation|L|; s|Compiling a graph for compile range|C|; s|Using cache directory: [^ ]*rank_0_0/|D:|" | tr "\n" " ")"
    grep -aoE "Graph capturing finished in [0-9]+ secs|took [0-9.]+ GiB" /tmp/server.log | sort -u | tr "\n" ";"; echo
    echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
    END=$(( $(date +%s) + SOAK_HOURS*3600 ))
    p=0
    while [ $(date +%s) -lt $END ]; do
      p=$((p+1))
      echo "PASS $p START $(date -u +%H:%M:%SZ)"
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM=soak-p$p python /tmp/perpos_client.py
      rc=$?
      echo "PASS $p END $(date -u +%H:%M:%SZ) rc=$rc"
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "SOAK ENGINE GONE at pass $p $(date -u +%H:%M:%SZ)"; grep -n -iE "Traceback|illegal|Error" /tmp/server.log | tail -20 | cut -c1-220; break; }
    done
    echo "SOAK DONE $(date -u +%H:%M:%SZ) passes=$p"
    curl -s http://127.0.0.1:'"$PORT"'/metrics | grep -E "^vllm:spec_decode_num_(drafts|draft_tokens|accepted_tokens)_total|^vllm:num_preemptions_total" | head -4
  ' > "$OUTD/soak-default.txt" 2>&1 &

# keep the engine log outside the container while it runs
( for i in $(seq 1 120); do sleep 300; docker ps --format '{{.Names}}' | grep -qx "$NAME" || break; docker exec "$NAME" cat /tmp/server.log > "$OUTD/serverlog-soak.txt.tmp" 2>/dev/null && mv -f "$OUTD/serverlog-soak.txt.tmp" "$OUTD/serverlog-soak.txt"; done ) &
wait
docker exec "$NAME" cat /tmp/server.log > "$OUTD/serverlog-soak.txt" 2>/dev/null
docker rm -f "$NAME" >/dev/null 2>&1
echo "SOAK CONTAINER REMOVED $(date -u +%H:%M:%SZ)" >> "$OUTD/soak-default.txt"
rm -f "$LOCK"
