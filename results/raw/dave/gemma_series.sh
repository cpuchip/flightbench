#!/bin/bash
# gemma 4 through judgment (v4) and the mission (v6), llama.cpp build 10510 on card 1, 16k context, same files as the board.
LSRV="C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/llama.cpp-pr27342/build-native/bin/llama-server.exe"
LMS="C:/Users/cpuch/.lmstudio/models"; OUTD="results/raw/dave"; export BASE=http://127.0.0.1:8143/v1
run_arm () {  # alias, gguf, extra args, ctx
  taskkill //F //IM llama-server.exe >/dev/null 2>&1; sleep 4
  CUDA_VISIBLE_DEVICES=1 "$LSRV" -m "$2" --port 8143 --host 127.0.0.1 -ngl 999 $3 -c $4 --jinja -a "$1" > "$OUTD/server-$1.log" 2>&1 &
  for i in $(seq 1 60); do code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8143/health 2>/dev/null); [ "$code" = "200" ] && break; sleep 5; done
  [ "$code" = "200" ] || { echo "!!! $1: server never healthy (ctx $4)"; tail -3 "$OUTD/server-$1.log"; return 1; }
  echo "########## $(date -u +%H:%M:%SZ) ARM $1 ctx=$4 ##########"
  MODEL="$1" THINK=none OUT="$OUTD/judgment-gemma.jsonl" timeout 900 python benches/judgment.py 2>&1 | grep -E "=== V4" | cut -c1-200
  for n in 1 2; do MODEL="$1" THINK=none SEAT=controller OUT="$OUTD/mission-gemma.jsonl" timeout 1500 python benches/mission.py 2>&1 | grep -E "=== V6" | cut -c1-260; done
}
run_arm gemma-e4b     "$LMS/unsloth/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-UD-Q4_K_XL.gguf" "" 16384
run_arm gemma-12b     "$LMS/lmstudio-community/gemma-4-12B-it-GGUF/gemma-4-12B-it-Q4_K_M.gguf" "" 16384
run_arm gemma-26b-a4b "$LMS/unsloth/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf" "" 16384
run_arm gemma-31b     "$LMS/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf" "" 16384 || run_arm gemma-31b "$LMS/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf" "" 8192
taskkill //F //IM llama-server.exe >/dev/null 2>&1
echo "GEMMA SERIES DONE $(date -u +%H:%M:%SZ)"
