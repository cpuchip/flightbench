#!/bin/bash
# TWO MORE CACHE-OFF BOOTS on card 1 (pc0c, pc0d), after the greedy pair. pc0a vs pc0b gave 17/32 identical
# trajectories with prefix caching off. Two readings compete: the boot-level state has a larger footprint
# when more is computed from scratch, or the cache-off regime is itself more sensitive to whatever the state
# is. Four cache-off boots separate them: a binary state predicts at most TWO trajectory groups among the
# four however many differing rows; more than two groups means the divergence is not one bit.
# Registered before the run. Engine line must read enable_prefix_caching False (void otherwise).
LOCK=/tmp/pc_more.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
while kill -0 744011 2>/dev/null; do sleep 30; done  # wait for the kernel-off boot (end of the card-0 queue) so card 0 clocks run with card 1 idle
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18021
VOL=qwen-cache-lane1; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name cheap_ctx
  NAME=$1; CC=$2
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=15 -e PREFIX_CACHE=1 -e VLLM_DFLASH2_LOOKUP_CHEAP_CTX=$CC -e EXTRA_ARGS=--no-enable-prefix-caching \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
    --entrypoint bash "$IMG" -c "$FIELD"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; tail -15 /tmp/server.log; exit 1; }
      echo "RESOLVED $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oE "enable_prefix_caching=(True|False)" /tmp/server.log | head -1) card1 $(nvidia-smi --query-gpu=pcie.link.width.current --format=csv,noheader 2>/dev/null | head -1 | sed "s/^/pcie_x/")"
      echo "SERVERLOG_BEGIN"; grep -aiE "speculative_config|SpeculativeConfig|rejection_sample|num_speculative_tokens|async_scheduling|async-scheduling|enable_prefix_caching|mamba_cache_mode|Capturing CUDA graph|cudagraph|force.first|first valid config|draft_logits|max_num_seqs|max_model_len" /tmp/server.log | head -60 | cut -c1-300; echo "SERVERLOG_END"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/pc-$NAME.txt" 2>&1
  echo "FFC-PC $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH' "$OUTD/pc-$NAME.txt" | head -2 | tr '\n' ' ')"
  echo "FFC-PC $NAME rows=$(grep -ac '^ROW ' "$OUTD/pc-$NAME.txt")"
}
arm pc0c 0
arm pc0d 0
echo "FFC-PC-MORE DONE $(date -u +%H:%M:%SZ)"
