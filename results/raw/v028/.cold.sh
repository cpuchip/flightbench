#!/bin/bash
# COLD-COMPILE PAIR AT THE DEFAULT. cgn7a compiled from scratch (raced the six GDN kernels, saved artefact
# 6cfcec20) and ran fast; cgn7b loaded that artefact with no race and ran slow (46.5 vs 33.7), engine config
# identical. Two default boots with VLLM_DISABLE_COMPILE_CACHE=1 (each compiles and races from scratch),
# winners printed, startup lines captured by the watcher. Void unless the RESOLVED line reads compiled>=1 and
# aot_loaded=0. Registered before the run: both cold boots fast (~23) means the loaded artefact carries the
# slow side and the four warm-loaded fast boots (r7a-d) loaded a good build while std7-type boots load a bad
# one; a cold boot landing slow means the compile itself can produce a slow build and the cache only replays
# it. Native control: that box's two cold boots sit inside its warm band (no effect there). Waits on sa0_7a.
#!/bin/bash
set -u
LOCK=/tmp/cold.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
while kill -0 744011 2>/dev/null; do sleep 30; done  # wait for the kernel-off boot (end of the card-0 queue)
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020
VOL=qwen-cache-lane0; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
BLOCK='sed -i "s|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\",\\\\\"rejection_sample_method\\\\\":\\\\\"block\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name
  NAME=$1; PRE="$FIELD"
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e TRITON_PRINT_AUTOTUNING=1 -e VLLM_DISABLE_COMPILE_CACHE=1 \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
    --entrypoint bash "$IMG" -c "$PRE"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      echo "SPEC_CFG_LINE $(grep -n "method.*dflash.*num_speculative_tokens" single-user/start_qwen.sh | head -1 | cut -c1-220)"
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; tail -15 /tmp/server.log; exit 1; }
      echo "RESOLVED DISABLE_COMPILE_CACHE=${VLLM_DISABLE_COMPILE_CACHE:-unset} compiled=$(grep -c "Compiling a graph" /tmp/server.log) aot_loaded=$(grep -c "Directly load AOT" /tmp/server.log) $(grep -oE "num_speculative_tokens.: [0-9]+" /tmp/server.log | head -1) $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oiE "rejection_sample_method[=: ]+[a-z]+|use_block_verification[=: ]+[A-Za-z]+" /tmp/server.log | head -2 | tr "\n" " ") $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
      echo "SERVERLOG_BEGIN"; grep -aiE "speculative_config|SpeculativeConfig|rejection_sample|num_speculative_tokens|async_scheduling|async-scheduling|enable_prefix_caching|Capturing CUDA graph|cudagraph|force.first|first valid config|draft_logits|max_num_seqs|max_model_len|autotun|best config" /tmp/server.log | head -400 | cut -c1-600; echo "SERVERLOG_END"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      ( while true; do echo "LINK $(date -u +%H:%M:%S) $(nvidia-smi --query-gpu=pcie.link.width.current,pcie.link.gen.current,clocks.sm,power.draw,utilization.gpu --format=csv,noheader)"; sleep 30; done ) &
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/cold-$NAME.txt" 2>&1
  echo "BLOCK-COLD $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH|SPEC_CFG_LINE' "$OUTD/cold-$NAME.txt" | head -2 | tr '\n' ' ' | cut -c1-300)"
  echo "BLOCK-COLD $NAME rows=$(grep -ac '^ROW ' "$OUTD/cold-$NAME.txt")"
}
arm cold7a
arm cold7b

echo "BLOCK-COLD DONE $(date -u +%H:%M:%SZ)"
