#!/bin/bash
# STEP-COST ATTRIBUTION on card 0. Observed 2026-09-05: DFLASH_TOKENS=15 (field set, lookup default on)
# costs 56 ms/step on card 0 against 23.3 ms/step at DFLASH_TOKENS=7, per prompt, reproducible to 1%
# across two boots (std1 and blk1), with the counters unchanged. The README measures 15 as +1% on chat
# on the maintainer's hardware, and the launcher default is 7. Three cells attribute the cost:
#   lk15off  DFLASH_TOKENS=15, VLLM_DFLASH2_LOOKUP=0   (verify width 15, no lookup)
#   t8       DFLASH_TOKENS=8,  lookup on              (one lookup position)
#   t11      DFLASH_TOKENS=11, lookup on              (four lookup positions)
# Registered before the run: if lk15off is ~23 ms the cost is the lookup's host work; if lk15off stays
# ~56 ms the cost is in the 15-wide verify or drafter path on this card; if t8 already pays most of it the
# cost is a step function at the first position past the trained block (a graph or padding boundary).
# Waits for the block redo (pid 731499) to exit; own lock; 30 s link sampling in every output.
set -u
LOCK=/tmp/lookup_cost.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
while kill -0 731499 2>/dev/null; do sleep 30; done  # wait for the block redo to exit
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020
VOL=qwen-cache-lane0; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
# field set; and for block cells, the rejection method appended to the same JSON
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
BLOCK='sed -i "s|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\",\\\\\"rejection_sample_method\\\\\":\\\\\"block\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name tokens extra-docker-args
  NAME=$1; TOK=$2; EXTRA=${3:-}; PRE="$FIELD"
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=$TOK -e PREFIX_CACHE=1 $EXTRA \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
    --entrypoint bash "$IMG" -c "$PRE"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      echo "SPEC_CFG_LINE $(grep -n "method.*dflash.*num_speculative_tokens" single-user/start_qwen.sh | head -1 | cut -c1-220)"
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; tail -15 /tmp/server.log; exit 1; }
      echo "RESOLVED DFLASH_TOKENS=$DFLASH_TOKENS VLLM_DFLASH2_LOOKUP=${VLLM_DFLASH2_LOOKUP:-unset} $(grep -oE "num_speculative_tokens[^,]{0,10}" /tmp/server.log | head -1) $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oiE "rejection_sample_method[=: ]+[a-z]+|use_block_verification[=: ]+[A-Za-z]+" /tmp/server.log | head -2 | tr "\n" " ") $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      ( while true; do echo "LINK $(date -u +%H:%M:%S) $(nvidia-smi --query-gpu=pcie.link.width.current,pcie.link.gen.current,clocks.sm,power.draw,utilization.gpu --format=csv,noheader)"; sleep 30; done ) &
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/lkcost-$NAME.txt" 2>&1
  echo "LKCOST $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH|SPEC_CFG_LINE' "$OUTD/lkcost-$NAME.txt" | head -2 | tr '\n' ' ' | cut -c1-300)"
  echo "LKCOST $NAME rows=$(grep -ac '^ROW ' "$OUTD/lkcost-$NAME.txt")"
}
arm lk15off 15 "-e VLLM_DFLASH2_LOOKUP=0"
arm t8 8
arm t11 11
echo "LKCOST DONE $(date -u +%H:%M:%SZ)"
