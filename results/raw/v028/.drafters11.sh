#!/bin/bash
# ARC THREE, DRAFTERS (registered 2026-09-05 before any boot; Michael: 'let's try those 3 things first ... see how they perform').
# Two community drafters for this exact target, run through the same harness as arc two (W4A16 target, eight-prompt cohort at the
# model's sampling, seeds 1-4, 32 rows, one boot each, card 0, card 1 idle), against the DFlash2 baseline on the same cohort
# (K=7: 23.2 ms/step, 3.798 tok/step; K=15 sync 56.5, kernel off 23.6). Apathy (onewhosighs, plain DFlash, block 16, BF16,
# trained against an NVFP4 target) via the launcher unpatched: DRAFT honoured from env, SPEC_CFG method already 'dflash', LOOKUP=0
# keeps the fork's dflash2 lookup out. DSpark (RadixArk, method dspark, serving block 7) via one sed on the method name, no
# draft_sample_method field on its first boot. Cells: ap7 (K=7), ap11 (K=11, QMAX 12, fast on this card), ap15sa0 (K=15,
# SPEC_ATTN=0: timing representative here, output caveat; threadchip runs K=15 kernel-on natively), ds7 (K=7). K>7 with LOOKUP=0
# keeps async on, so the KV pin is raised as in a15on2. Readouts: tok/step, ms/step, tok/s, per-position, completion lengths,
# and the boot's load/compile sequence. Predictions: ap7 below DFlash2 at 7 (its card: acceptance dips near position 5);
# ap15 is the question (a trained tail against the lookup's 1-2 percent tail); ds7 at or below DFlash2. Void for a cell if
# NO HEALTH; the FAILLOG is the reading then.
LOCK=/tmp/drafters11.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
while kill -0 789348 2>/dev/null; do sleep 30; done  # wait for the tenth chain (w15p3) to end at its own boundary
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020
VOL=qwen-cache-lane0; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
BLOCK='sed -i "s|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\",\\\\\"rejection_sample_method\\\\\":\\\\\"block\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name tokens extra-docker-args [launcher-sed] [nofield]
  NAME=$1; TOK=$2; EXTRA=${3:-}; PRE="$FIELD${4:-}"; [ "${5:-}" = nofield ] && PRE="${4:-}"
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
      echo "SEQUENCE $(grep -oE "Directly load AOT compilation|Compiling a graph for compile range|Using cache directory: [^ ]*rank_0_0/[a-z0-9_]+" /tmp/server.log | sed -E "s|Directly load AOT compilation|L|; s|Compiling a graph for compile range|C|; s|Using cache directory: [^ ]*rank_0_0/|D:|" | tr "
" " ")"
      echo "RESOLVED $(grep -oE "max_model_len.: [0-9]+" /tmp/server.log | head -1) $(grep -oE "kv_cache_memory_bytes.: [0-9]+" /tmp/server.log | head -1) DFLASH_TOKENS=$DFLASH_TOKENS DRAFT=${DRAFT:-default} LOOKUP=${LOOKUP:-unset} QMAX=${VLLM_SPEC_DECODE_ATTN_QMAX:-unset} SPEC_ATTN=${SPEC_ATTN:-unset} VLLM_SPEC_DECODE_ATTN=${VLLM_SPEC_DECODE_ATTN:-unset} FORCE_FIRST=${VLLM_TRITON_FORCE_FIRST_CONFIG:-unset} ASYNC_SCHED=${ASYNC_SCHED:-unset} $(grep -oE "async_scheduling[=: ]+(True|False)" /tmp/server.log | head -1) $(grep -oE "\-\-(no-)?async-scheduling" /tmp/server.log | head -1) $(grep -oE "num_speculative_tokens[^,]{0,10}" /tmp/server.log | head -1) $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oiE "rejection_sample_method[=: ]+[a-z]+|use_block_verification[=: ]+[A-Za-z]+" /tmp/server.log | head -2 | tr "\n" " ") $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
      echo "SERVERLOG_BEGIN"; grep -aiE "speculative_config|SpeculativeConfig|rejection_sample|num_speculative_tokens|async_scheduling|async-scheduling|enable_prefix_caching|Capturing CUDA graph|cudagraph|force.first|first valid config|draft_logits|max_num_seqs|max_model_len|autotun|best config" /tmp/server.log | head -400 | cut -c1-600; echo "SERVERLOG_END"
      echo "NONDEFAULT_LINE $(grep -m1 "non-default args" /tmp/server.log | cut -c1-3000)"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      ( while true; do echo "LINK $(date -u +%H:%M:%S) $(nvidia-smi --query-gpu=pcie.link.width.current,pcie.link.gen.current,clocks.sm,power.draw,utilization.gpu --format=csv,noheader)"; sleep 30; done ) &
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/drf-$NAME.txt" 2>&1
  echo "DRAFTERS $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH|SPEC_CFG_LINE|SEQUENCE' "$OUTD/drf-$NAME.txt" | head -2 | tr '\n' ' ' | cut -c1-300)"
  echo "DRAFTERS $NAME rows=$(grep -ac '^ROW ' "$OUTD/drf-$NAME.txt")"
}
DSPARK_SED='sed -i "s|\\\\\"method\\\\\":\\\\\"dflash\\\\\"|\\\\\"method\\\\\":\\\\\"dspark\\\\\"|" /app/single-user/start_qwen.sh; '
AP=/app/models/Apathy-Qwen3.8-27B-DFlash-drafter-v2; DS=/app/models/Qwen3.8-27B-DSpark
# 13:20Z: ap7 (kernel on, default memory) died at engine start with "Triton Error [CUDA]: an illegal memory access" after
# loading 18.09 GiB and capturing graphs (drf-ap7-void.txt). Re-armed as diagnostics: ap7sa0 turns the fork's split-KV verify
# kernel off (if it boots, the kernel is incompatible with the plain DFlash class); ap7lite keeps the kernel on with a light
# memory profile (MAX_LEN=16384, KV_MEM= falls back to GPU_UTIL sizing) to separate a memory fault from a kernel fault;
# bl7off is the DFlash2 baseline with lookup drafting off, so ap7 has a like-for-like baseline (the 23.2 / 3.798 boots ran
# at the launcher default, LOOKUP=1); ds7 as registered. Readings: ap7sa0 boots and ap7lite does not -> kernel; both boot ->
# memory; neither -> the DFlash path itself in this fork, FAILLOG is the reading.
# 13:5xZ: MAX_LEN is overwritten on the DFlash path by DFLASH_MAX_LEN (launcher :360), found by threadchip on his ap7c; ap7lite
# re-armed with the variable the launcher honours. ap7sa0 ran in the first chain (detached, its file is drf-ap7sa0.txt).
# SECOND CHAIN (registered 14:0xZ). ap7lite died at the memory floor before capture (could-not-run), so the kernel-on test uses
# the matched ap7g design (GPU_UTIL=0.97 on an idle card, DFLASH_MAX_LEN=8192, KV_MEM empty): serves = the IMA was memory-related
# with the kernel's buffers; dies with the IMA after capture = the kernel. The kernel-off width cells use the memory that ap7sa0
# served with (the pin; raised 256 MiB for async at K>7). ds7sa0 is the fallback if ds7 dies the way ap7 did.
# ELEVENTH CHAIN (registered 16:1xZ). ap7p3's captured sequence reads L D:dflash_head C: the backbone artefact loaded and the
# drafter's head compiled in-process, the mixed boot that arc two calls the slow class (mix7chk, the same shape with the DFlash2
# head, reproduces 45.0 ms/step with dedicated at the ceiling and shared 358); and the first sampler shows ap7p3's rows at
# dedicated 23361 / shared 214, about 130 MiB over the ceiling. So the plain-DFlash residual (49.4 against bl7p3's 23.3) has
# two candidate causes that are not the path: the boot class and the ceiling. ap7p3b is ap7p3 run again unchanged; the head
# artefact ap7p3 compiled is now in the cache, so a second boot should load it (L L) and shed the compile-time working set.
# Readings registered before it boots: L L, shared at baseline, 25-35 ms/step = the residual was the slow class (and its
# memory face), item 14's 'mechanism unknown' resolves into the arc-two state, and the 3090's 30.9 is the plain-DFlash cost;
# L L, shared at baseline, ~49 = a real path cost with both confounders removed; a compiled head again = the artefact did not
# persist for this drafter and the cell is repeated once more before anything is read.
arm ap7p3b 7 "-e DRAFT=$AP -e LOOKUP=0 -e KV_MEM=3000000000 -e DFLASH_MAX_LEN=8192"
echo "DRAFTERS11 DONE $(date -u +%H:%M:%SZ)"
