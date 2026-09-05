#!/bin/bash
# WIDTH-7 CACHE-OFF PAIR on card 1 (p7a, p7b), after the width-15 cache-off boots. The default
# replays across five boots on card 0 and two on the native 3090, all with prefix caching ON, and at
# width 15 the cache is exactly what suppressed the boot state on the native box. Two worlds fit that:
# the state is specific to the width-15 path, or it reaches width 7 and the cache hides it. Two sampled
# boots at the default with --no-enable-prefix-caching decide it here (the native box runs the same pair).
# Void unless the engine line reads enable_prefix_caching False. Registered before the run: identical on
# 32 of 32 means the state is a width-15-path property (the scoping in the doc holds and is stronger);
# a split means the state reaches the default and the cache hides it, and the width-15 framing is rewritten.
#!/bin/bash
LOCK=/tmp/p7.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
while kill -0 748699 2>/dev/null; do sleep 30; done  # wait for the extra width-15 cache-off boots (pc0c, pc0d; re-armed 10:58Z)
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
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e EXTRA_ARGS=--no-enable-prefix-caching \
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
    ' > "$OUTD/p7-$NAME.txt" 2>&1
  echo "FFC-P7 $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH' "$OUTD/p7-$NAME.txt" | head -2 | tr '\n' ' ')"
  echo "FFC-P7 $NAME rows=$(grep -ac '^ROW ' "$OUTD/p7-$NAME.txt")"
}
arm p7a 0
arm p7b 0
echo "FFC-P7 DONE $(date -u +%H:%M:%SZ)"
