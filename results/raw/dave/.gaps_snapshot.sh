#!/bin/bash
# The gaps, one clean series, its own port (8144): 26B and 31B on the final scorer, qwen3.8 Q4_K_M off/on, E4B mission.
LSRV="C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/llama.cpp-pr27342/build-native/bin/llama-server.exe"
LMS="C:/Users/cpuch/.lmstudio/models"; OUTD="results/raw/dave"; PORT=8144; export BASE=http://127.0.0.1:$PORT/v1
run_arm () {  # alias, gguf, ctx, think, judgment(1/0), missions
  CUDA_VISIBLE_DEVICES=1 "$LSRV" -m "$2" --port $PORT --host 127.0.0.1 -ngl 999 -c $3 --jinja -a "$1" > "$OUTD/server-gaps-$1.log" 2>&1 &
  SPID=$!
  for i in $(seq 1 90); do code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$PORT/health 2>/dev/null); [ "$code" = "200" ] && break; sleep 5; done
  if [ "$code" != "200" ]; then echo "!!! $1: server never healthy (ctx $3)"; tail -3 "$OUTD/server-gaps-$1.log"; kill $SPID 2>/dev/null; sleep 3; return 1; fi
  echo "########## $(date -u +%H:%M:%SZ) ARM $1 ctx=$3 think=$4 ##########"
  if [ "$5" = 1 ]; then MODEL="$1" THINK=$4 OUT="$OUTD/judgment-gaps.jsonl" timeout 900 python benches/judgment.py 2>&1 | grep -E "=== V4" | cut -c1-200; fi
  for n in $(seq 1 $6); do MODEL="$1" THINK=$4 SEAT=controller OUT="$OUTD/mission-gaps.jsonl" timeout 1500 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | cut -c1-260; done
  kill $SPID 2>/dev/null; sleep 4
}
run_arm gemma-26b-a4b "$LMS/unsloth/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf" 16384 none 1 2
run_arm gemma-31b     "$LMS/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf" 16384 none 1 2
run_arm qwen-q4km-off "$LMS/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf" 16384 off 1 2
run_arm qwen-q4km-on  "$LMS/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-Q4_K_M.gguf" 16384 on 1 2
run_arm gemma-e4b     "$LMS/unsloth/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-UD-Q4_K_XL.gguf" 16384 none 0 2
echo "GAPS SERIES DONE $(date -u +%H:%M:%SZ)"
