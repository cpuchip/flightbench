#!/bin/bash
# ARM 1: per-position acceptance and drafting shorter than trained. Widths 3,4,5,6,7. Below 7 the
# drafted block equals the setting (no clamp), so this is the first published look at k<7 on this
# stack. Field set (production config). Registered before the run: the per-position acceptance
# curve is steeply decreasing; if positions 5-7 accept under ~10% the wall-clock optimum (decode
# tok/s) sits below 7 because fewer verify positions cost less per step for nearly the same
# accepted tokens. Falsifier: if tok_s is monotone increasing in width up to 7, drafting shorter
# buys nothing on this box. Card 0, own cache volume.
set -u
LOCK=/tmp/width_arms.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020
VOL=qwen-cache-lane0; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name width
  NAME=$1; W=$2
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=$W -e PREFIX_CACHE=1 \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
    --entrypoint bash "$IMG" -c "$FIELD"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; tail -15 /tmp/server.log; exit 1; }
      echo "RESOLVED $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oE "drafting [0-9]+ tokens per step|num_speculative_tokens[=: ]+[0-9]+" /tmp/server.log | head -2 | tr "\n" " ") $(grep -oiE "enable_prefix_caching=[A-Za-z]+" /tmp/server.log | head -1)"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/width-$NAME.txt" 2>&1
  echo "WIDTH $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH' "$OUTD/width-$NAME.txt" | head -2 | tr '\n' ' ')"
  echo "WIDTH $NAME rows=$(grep -ac '^ROW ' "$OUTD/width-$NAME.txt")"
}
for W in 7 5 4 3 6; do arm "w$W" $W; done
echo "WIDTH ARMS DONE $(date -u +%H:%M:%SZ)"
