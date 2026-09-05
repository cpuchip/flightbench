#!/bin/bash
# ARM 2, wall-clock half, on the FAST card. Card 1 is PCIe x4 and its decode rate is a lane
# artefact, so the H1 reading ("+8% decode with the long block forced at short context") has to be
# measured on card 0. Two end cells only, cc0 and cc16384, same client, same cohort, same field
# sed; the per-position discriminator already comes from card 1 and is counter-based. Queued
# behind arm 1 (waits for the w* containers to clear), own lock, lane0 cache volume.
set -u
LOCK=/tmp/cheapctx_card0.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
until [ -z "$(docker ps --format '{{.Names}}' | grep -E '^(w[0-9]|std[0-9]|blk[0-9])$')" ]; do sleep 30; done
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020
VOL=qwen-cache-lane0; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name cheap_ctx
  NAME=$1; CC=$2
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=15 -e PREFIX_CACHE=1 -e VLLM_DFLASH2_LOOKUP_CHEAP_CTX=$CC \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
    --entrypoint bash "$IMG" -c "$FIELD"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; tail -15 /tmp/server.log; exit 1; }
      echo "RESOLVED $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) CHEAP_CTX=${VLLM_DFLASH2_LOOKUP_CHEAP_CTX} card0 $(nvidia-smi --query-gpu=pcie.link.width.current --format=csv,noheader 2>/dev/null | head -1 | sed "s/^/pcie_x/")"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/cheapctx-$NAME.txt" 2>&1
  echo "CHEAPCTX0 $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH' "$OUTD/cheapctx-$NAME.txt" | head -2 | tr '\n' ' ')"
  echo "CHEAPCTX0 $NAME rows=$(grep -ac '^ROW ' "$OUTD/cheapctx-$NAME.txt")"
}
arm c0cc0     0
arm c0cc16384 16384
echo "CHEAPCTX CARD0 DONE $(date -u +%H:%M:%SZ)"
