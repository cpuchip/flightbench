#!/usr/bin/env bash
# Round trip, stage 4: boot the fork's launcher with a given DFlash2 head and run the 32-request per-position
# client against it, in THIS container (GPU 1 via CUDA_VISIBLE_DEVICES already set). Mirrors flightbench's
# .drafters*.sh bl7p3 arm (the baseline): SPEC=dflash2 CTX=fast DFLASH_TOKENS=7 PREFIX_CACHE=1 INT8_ACT=int8
# INT8_LAYERS=all PREFILL_ATTN=int8 GPU_UTIL=0.90, draft_sample_method probabilistic, LOOKUP=0, DFLASH_MAX_LEN=8192,
# KV_MEM as given (3e9 = the bl7p3 pin).
# SHIPPED-PROFILE variant (2026-09-06): no KV_MEM, no DFLASH_MAX_LEN, i.e. the launcher defaults the soak ran (the KVM arg is accepted and ignored).
# Usage: bash serve_arm_shipped.sh <ARM> <DRAFT_DIR> <KV_MEM> <OUT_TXT> [SEEDS=1,2,3,4] [NPROMPTS=8]
# Exit: 0 rows produced; 2 no health; 3 client failed.
set -u
ARM=$1; DRAFT_DIR=$2; KVM=$3; OUT=$4; SEEDS=${5:-1,2,3,4}; NPROMPTS=${6:-8}
PORT=${PORT:-18021}
stamp() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
if [ -z "${VLLM_API_KEY:-}" ]; then
  VLLM_API_KEY=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
  export VLLM_API_KEY
fi
# the bl7p3 arm's launcher patch: draft_sample_method probabilistic on the dflash spec config (1x)
grep -q 'dflash.*draft_sample_method' /app/single-user/start_qwen.sh || \
  sed -i 's|\\"num_speculative_tokens\\":$DRAFT_TOKENS}|\\"num_speculative_tokens\\":$DRAFT_TOKENS,\\"draft_sample_method\\":\\"probabilistic\\"}|' /app/single-user/start_qwen.sh
{
  stamp "ARM $ARM DRAFT=$DRAFT_DIR KV_MEM=$KVM PORT=$PORT SEEDS=$SEEDS NPROMPTS=$NPROMPTS"
  echo "SPEC_CFG_LINE $(grep -n "method.*dflash.*num_speculative_tokens" /app/single-user/start_qwen.sh | head -1 | cut -c1-220)"
  echo "DRAFT_FILES $(ls -la "$DRAFT_DIR" | tr -s ' ' | cut -d' ' -f5,9 | tr '\n' ' ')"
} > "$OUT" 2>&1
rm -f /tmp/server.log
cd /app
env -u MODEL HOME=/cache PORT=$PORT SPEC=dflash2 CTX=fast DFLASH_TOKENS=7 PREFIX_CACHE=1 \
  INT8_ACT=int8 INT8_LAYERS='mlp|linear_attn|self_attn' PREFILL_ATTN=int8 GPU_UTIL=0.90 \
  VLLM_WSL2_ENABLE_PIN_MEMORY=1 VLLM_NO_USAGE_STATS=1 \
  DRAFT="$DRAFT_DIR" PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False \
  nohup bash /app/single-user/start_qwen.sh > /tmp/server.log 2>&1 &
SRV=$!
echo "SERVER_PID $SRV" >> "$OUT"
UP=0
for i in $(seq 1 240); do
  sleep 5
  if curl -sf -o /dev/null -H "Authorization: Bearer $VLLM_API_KEY" http://127.0.0.1:$PORT/health; then UP=1; break; fi
  kill -0 $SRV 2>/dev/null || break
done
if [ "$UP" != 1 ]; then
  {
    stamp "NO HEALTH"
    echo "FAILLOG_BEGIN"; grep -n -m1 -B3 -A40 -iE "Traceback|Error|error|assert" /tmp/server.log | cut -c1-300 | head -80; echo "FAILLOG_END"
    tail -15 /tmp/server.log | cut -c1-300
  } >> "$OUT" 2>&1
  pkill -P $SRV 2>/dev/null; kill $SRV 2>/dev/null; pkill -f "vllm serve" 2>/dev/null; sleep 10
  cp /tmp/server.log "${OUT%.txt}.server.log" 2>/dev/null
  exit 2
fi
{
  stamp "HEALTH OK"
  echo "SEQUENCE $(grep -oE "Directly load AOT compilation|Compiling a graph for compile range|Using cache directory: [^ ]*rank_0_0/[a-z0-9_]+" /tmp/server.log | sed -E "s|Directly load AOT compilation|L|; s|Compiling a graph for compile range|C|; s|Using cache directory: [^ ]*rank_0_0/|D:|" | tr "\n" " ")"
  echo "RESOLVED $(grep -oE "max_model_len.: [0-9]+" /tmp/server.log | head -1) $(grep -oE "kv_cache_memory_bytes.: [0-9]+" /tmp/server.log | head -1) DFLASH_TOKENS=7 DRAFT=$DRAFT_DIR LOOKUP=default $(grep -oE "num_speculative_tokens[^,]{0,10}" /tmp/server.log | head -1) $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
  echo "SERVERLOG_BEGIN"; grep -aiE "speculative_config|SpeculativeConfig|rejection_sample|num_speculative_tokens|enable_prefix_caching|Loading weights took|Model loading took|draft|dflash|max_num_seqs|max_model_len|Available KV cache memory|GPU KV cache size" /tmp/server.log | grep -v -i autotun | head -120 | cut -c1-400; echo "SERVERLOG_END"
  echo "NONDEFAULT_LINE $(grep -m1 "non-default args" /tmp/server.log | cut -c1-3000)"
  echo "GPU_AFTER_BOOT $(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader | tr '\n' ' ')"
} >> "$OUT" 2>&1
PORT=$PORT VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" SEEDS="$SEEDS" NPROMPTS="$NPROMPTS" python /work/perpos_client.py >> "$OUT" 2>&1
RC=$?
stamp "CLIENT exit $RC rows=$(grep -c '^ROW ' "$OUT")" >> "$OUT"
pkill -P $SRV 2>/dev/null; kill $SRV 2>/dev/null; pkill -f "vllm serve" 2>/dev/null
for i in $(seq 1 30); do sleep 2; kill -0 $SRV 2>/dev/null || break; done
sleep 5
cp /tmp/server.log "${OUT%.txt}.server.log" 2>/dev/null
stamp "SERVER DOWN gpu=$(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader | tr '\n' ' ')" >> "$OUT"
[ "$RC" = 0 ] || exit 3
grep -q '^ROW ' "$OUT" || exit 3
exit 0
