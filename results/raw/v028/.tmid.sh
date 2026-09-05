#!/bin/bash
# ISOLATE QMAX. Source read (spec_decode_attn.py in the image, sha 53ee3e78, unpatched on the other box
# too): the split-KV verify kernel plans its tiles on the ACTUAL max_query_len per step (line 217), not
# on qmax, so a tile or 16-query shape boundary is excluded by source; qmax enters as the partial-buffer
# size (linear, line 183) and as a tl.constexpr in both kernels (separate compilation, lines 67, 147).
# t8 (qmax 9) at 23.2 argues against the linear half. The launcher exports VLLM_SPEC_DECODE_ATTN_QMAX
# from an inherited value if set (line 223): q16_7 = DFLASH_TOKENS=7 with QMAX=16, identical width,
# positions per step and tile plan, only qmax changed (raising it above the need is safe; the kernel
# asserts max_query_len <= qmax, so the reverse would trip). Registered: q16_7 near 56 means qmax alone
# is the mechanism (that kernel compiled at that constexpr on this card); near 23 exonerates qmax, and
# t11 behind it brackets the width step. The native box runs the same cell as control (expected flat).
#!/bin/bash
LOCK=/tmp/tmid.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
while kill -0 740118 2>/dev/null; do sleep 30; done  # wait for the graphs-off pair (end of the card-0 queue)
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020
VOL=qwen-cache-lane0; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
BLOCK='sed -i "s|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\",\\\\\"rejection_sample_method\\\\\":\\\\\"block\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name tokens extra-docker-args
  NAME=$1; TOK=$2; EXTRA=${3:-}; PRE="$FIELD"
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=$TOK -e PREFIX_CACHE=1 -e TRITON_PRINT_AUTOTUNING=1 $EXTRA \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
    --entrypoint bash "$IMG" -c "$PRE"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      echo "SPEC_CFG_LINE $(grep -n "method.*dflash.*num_speculative_tokens" single-user/start_qwen.sh | head -1 | cut -c1-220)"
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; echo "FAILLOG_BEGIN"; grep -n -m1 -B3 -A40 -iE "Traceback|Error|error|assert" /tmp/server.log | cut -c1-300 | head -80; echo "FAILLOG_END"; tail -15 /tmp/server.log | cut -c1-300; exit 1; }
      echo "RESOLVED DFLASH_TOKENS=$DFLASH_TOKENS QMAX=${VLLM_SPEC_DECODE_ATTN_QMAX:-unset} SPEC_ATTN=${SPEC_ATTN:-unset} VLLM_SPEC_DECODE_ATTN=${VLLM_SPEC_DECODE_ATTN:-unset} FORCE_FIRST=${VLLM_TRITON_FORCE_FIRST_CONFIG:-unset} ASYNC_SCHED=${ASYNC_SCHED:-unset} $(grep -oE "async_scheduling[=: ]+(True|False)" /tmp/server.log | head -1) $(grep -oE "\-\-(no-)?async-scheduling" /tmp/server.log | head -1) $(grep -oE "num_speculative_tokens[^,]{0,10}" /tmp/server.log | head -1) $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oiE "rejection_sample_method[=: ]+[a-z]+|use_block_verification[=: ]+[A-Za-z]+" /tmp/server.log | head -2 | tr "\n" " ") $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
      echo "SERVERLOG_BEGIN"; grep -aiE "speculative_config|SpeculativeConfig|rejection_sample|num_speculative_tokens|async_scheduling|async-scheduling|enable_prefix_caching|Capturing CUDA graph|cudagraph|force.first|first valid config|draft_logits|max_num_seqs|max_model_len|autotun|best config" /tmp/server.log | head -400 | cut -c1-600; echo "SERVERLOG_END"
      echo "NONDEFAULT_LINE $(grep -m1 "non-default args" /tmp/server.log | cut -c1-3000)"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      ( while true; do echo "LINK $(date -u +%H:%M:%S) $(nvidia-smi --query-gpu=pcie.link.width.current,pcie.link.gen.current,clocks.sm,power.draw,utilization.gpu --format=csv,noheader)"; sleep 30; done ) &
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/tmid-$NAME.txt" 2>&1
  echo "LKCOST $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH|SPEC_CFG_LINE' "$OUTD/tmid-$NAME.txt" | head -2 | tr '\n' ' ' | cut -c1-300)"
  echo "LKCOST $NAME rows=$(grep -ac '^ROW ' "$OUTD/tmid-$NAME.txt")"
}
arm q16_7 7 "-e VLLM_SPEC_DECODE_ATTN_QMAX=16"
arm t11 11
echo "LKCOST TMID DONE $(date -u +%H:%M:%SZ)"
