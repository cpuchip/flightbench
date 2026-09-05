#!/bin/bash
# THE PARTIAL-RECOMPILE PAIR (registered 2026-09-05 before it runs; doc section 'The slow side has a boot state').
# Lineage table: every unexplained slow card-0 boot (std7, a7off2, cgn7b) loaded artefact 1 and recompiled 2 and 3;
# no partial-1, full-compile or full-load boot at normal config was slow. r7e: the launcher default with the lineage's
# artefacts 2 and 3 (75da7859, 04cf860e) moved to /cache/.cache/vllm/held-20260905/ on lane0, so it must load 1 and
# recompile two. PREDICTED 45 ms/step; 23 falsifies partial-2 as sufficient. r7f: the default after it, loading all three.
# PREDICTED 23; 45 says the slot r7e wrote poisons loaders (the 2026-09-02 reading). Card 1 runs pc0c/pc0d concurrently
# (neighbour recorded by the LINK sampler; the effect under test is 2x). Void unless r7e's RESOLVED reads compiled=2 aot_loaded=1.
set -u
LOCK=/tmp/mix7.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
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
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 -e TRITON_PRINT_AUTOTUNING=1 \
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
    ' > "$OUTD/mix-$NAME.txt" 2>&1
  echo "BLOCK-MIX $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH|SPEC_CFG_LINE' "$OUTD/mix-$NAME.txt" | head -2 | tr '\n' ' ' | cut -c1-300)"
  echo "BLOCK-MIX $NAME rows=$(grep -ac '^ROW ' "$OUTD/mix-$NAME.txt")"
}
MSYS_NO_PATHCONV=1 docker run --rm -v qwen-cache-lane0:/cache alpine sh -c 'D=/cache/.cache/vllm/torch_compile_cache/torch_aot_compile; H=/cache/.cache/vllm/held-20260905; mkdir -p $H; for h in 75da78594620167c51af389e7c81d710f438ac7722692f474444a0873a8ecaa3 04cf860e483a8315252ccec6d645181cd86fb72690fe08f37b0563dc63f90248; do if [ -d $D/$h ]; then mv $D/$h $H/ && echo "HELD $h"; else echo "MISSING $h"; fi; done; echo "AOT entries now: $(ls -A $D | wc -l)"'
arm r7e
arm r7f

echo "BLOCK-MIX DONE $(date -u +%H:%M:%SZ)"
