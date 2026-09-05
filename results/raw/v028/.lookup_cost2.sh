#!/bin/bash
# STEP-COST ATTRIBUTION, REVISED after the fresh-eyes review (docs/reviews/arc2-fresh-eyes-opus.md):
# start_qwen.sh:291-296 sets ASYNC_SCHED=0 whenever VLLM_DFLASH2_LOOKUP=1 and DRAFT_TOKENS > 7, and
# line 658 turns that into --no-async-scheduling. So every 56 ms/step cell on card 0 ran synchronous
# scheduling and every 23 ms/step cell ran async; the first design (lookup off at 15) would have
# silently restored async and could not separate lookup from scheduling. The launcher comment says the
# cost of losing async at batch 1 is under 1% (the maintainer's native hardware); this box is WSL2.
#   a7off    DFLASH_TOKENS=7,  ASYNC_SCHED=0            (default width, synchronous scheduling)
#   a15on    DFLASH_TOKENS=15, ASYNC_SCHED=1, lookup on  (reproduction mode, async forced back on;
#                                                        the adaptive length then pads to 15 every step)
#   lk15off  DFLASH_TOKENS=15, VLLM_DFLASH2_LOOKUP=0     (15-wide verify, no lookup, async stays on)
# Registered before the run: a7off near 56 ms and a15on near 23 to 25 ms means the 2.4x is synchronous
# scheduling on this box (a per-step host round trip, cheap native, expensive under WSL2), not width and
# not the lookup; lk15off equal to a15on then says the lookup's own host work is free, above it says it
# is not. Fallback: a7off near 23 ms means scheduling is not the cost and it lives in the 15-wide path.
# Runs as the first link of one sequential chain behind the block redo (pid 731499); own lock.
set -u
LOCK=/tmp/lookup_cost2.lock
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
      echo "RESOLVED DFLASH_TOKENS=$DFLASH_TOKENS VLLM_DFLASH2_LOOKUP=${VLLM_DFLASH2_LOOKUP:-unset} ASYNC_SCHED=${ASYNC_SCHED:-unset} $(grep -oE "async_scheduling[=: ]+(True|False)" /tmp/server.log | head -1) $(grep -oE "\-\-(no-)?async-scheduling" /tmp/server.log | head -1) $(grep -oE "num_speculative_tokens[^,]{0,10}" /tmp/server.log | head -1) $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oiE "rejection_sample_method[=: ]+[a-z]+|use_block_verification[=: ]+[A-Za-z]+" /tmp/server.log | head -2 | tr "\n" " ") $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
      echo "SERVERLOG_BEGIN"; grep -aiE "speculative_config|SpeculativeConfig|rejection_sample|num_speculative_tokens|async_scheduling|async-scheduling|enable_prefix_caching|Capturing CUDA graph|cudagraph|force.first|first valid config|draft_logits|max_num_seqs|max_model_len" /tmp/server.log | head -60 | cut -c1-300; echo "SERVERLOG_END"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      ( while true; do echo "LINK $(date -u +%H:%M:%S) $(nvidia-smi --query-gpu=pcie.link.width.current,pcie.link.gen.current,clocks.sm,power.draw,utilization.gpu --format=csv,noheader)"; sleep 30; done ) &
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/lkcost-$NAME.txt" 2>&1
  echo "LKCOST $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH|SPEC_CFG_LINE' "$OUTD/lkcost-$NAME.txt" | head -2 | tr '\n' ' ' | cut -c1-300)"
  echo "LKCOST $NAME rows=$(grep -ac '^ROW ' "$OUTD/lkcost-$NAME.txt")"
}
arm a7off 7 "-e ASYNC_SCHED=0"
arm a15on 15 "-e ASYNC_SCHED=1"
arm lk15off 15 "-e VLLM_DFLASH2_LOOKUP=0"
echo "LKCOST DONE $(date -u +%H:%M:%SZ)"
