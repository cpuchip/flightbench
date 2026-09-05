#!/bin/bash
# lk15off REPEAT with the knob the IMAGE honours. The launcher inside image pr43-6869c80 is older than
# the checkout (680 lines against 800): its line 206 reads export VLLM_DFLASH2_LOOKUP=${LOOKUP:-1}
# unconditionally, so a container env VLLM_DFLASH2_LOOKUP=0 is overwritten to 1 and the first lk15off
# ran with the lookup ON (engine log carries the lookup's "drafting 7 tokens per step" line; trajectory
# bit-identical to std1). LOOKUP is the alias that image honours. This cell: DFLASH_TOKENS=15, LOOKUP=0,
# ASYNC_SCHED=0 pinned so only the lookup differs from std1 (lookup off = the drafter is asked for the whole
# 15-token block, rounds 15.000 always). Void: engine log must NOT contain "drafting 7 tokens per step";
# rounds 15.000; engine line async False and 15. Registered: steady ms/step near 56 = the 15-wide verify
# path costs the 2.4x without the lookup; near 23 = the lookup path is the cost after all.
# Waits on the width-15 cause cells (pid 736463), last of the card-0 queue.
set -u
LOCK=/tmp/lk15off2.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
while kill -0 736463 2>/dev/null; do sleep 30; done  # wait for the width-15 cause cells to exit
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
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; echo "FAILLOG_BEGIN"; grep -n -m1 -B3 -A40 -iE "Traceback|Error|error|assert" /tmp/server.log | cut -c1-300 | head -80; echo "FAILLOG_END"; tail -15 /tmp/server.log | cut -c1-300; exit 1; }
      echo "RESOLVED DFLASH_TOKENS=$DFLASH_TOKENS LOOKUP=${LOOKUP:-unset} ASYNC_SCHED=${ASYNC_SCHED:-unset} lookup_log_line=$(grep -c "drafting 7 tokens per step" /tmp/server.log) $(grep -oE "async_scheduling[=: ]+(True|False)" /tmp/server.log | head -1) $(grep -oE "\-\-(no-)?async-scheduling" /tmp/server.log | head -1) $(grep -oE "num_speculative_tokens[^,]{0,10}" /tmp/server.log | head -1) $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oiE "rejection_sample_method[=: ]+[a-z]+|use_block_verification[=: ]+[A-Za-z]+" /tmp/server.log | head -2 | tr "\n" " ") $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
      echo "SERVERLOG_BEGIN"; grep -aiE "speculative_config|SpeculativeConfig|rejection_sample|num_speculative_tokens|async_scheduling|async-scheduling|enable_prefix_caching|Capturing CUDA graph|cudagraph|force.first|first valid config|draft_logits|max_num_seqs|max_model_len" /tmp/server.log | head -60 | cut -c1-2500; echo "SERVERLOG_END"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      ( while true; do echo "LINK $(date -u +%H:%M:%S) $(nvidia-smi --query-gpu=pcie.link.width.current,pcie.link.gen.current,clocks.sm,power.draw,utilization.gpu --format=csv,noheader)"; sleep 30; done ) &
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/lkcost-$NAME.txt" 2>&1
  echo "LKCOST $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH|SPEC_CFG_LINE' "$OUTD/lkcost-$NAME.txt" | head -2 | tr '\n' ' ' | cut -c1-300)"
  echo "LKCOST $NAME rows=$(grep -ac '^ROW ' "$OUTD/lkcost-$NAME.txt")"
}
arm lk15off2 15 "-e LOOKUP=0 -e ASYNC_SCHED=0"
echo "LKCOST LK15OFF2 DONE $(date -u +%H:%M:%SZ)"
