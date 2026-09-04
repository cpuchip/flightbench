#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
D=results/raw/v028
for k in k1_kvarn_backend k2_runner_only; do docker build -t "qwen38-27b-rtx3090:stock028-$k" "$D/.bisect-$k" > "$D/build-bisect-$k.log" 2>&1 && echo "BUILD $k ok" || echo "BUILD $k FAILED"; done
for k in k1_kvarn_backend k2_runner_only; do docker image inspect "qwen38-27b-rtx3090:stock028-$k" >/dev/null 2>&1 && bash $D/.stock_bisect_v2_lane0.sh "qwen38-27b-rtx3090:stock028-$k" "$k"; done
echo "KVARN SPLIT DONE $(date -u +%H:%M:%SZ)"
