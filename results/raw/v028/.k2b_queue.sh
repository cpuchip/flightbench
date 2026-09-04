#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
D=results/raw/v028
docker build -t qwen38-27b-rtx3090:stock028-k2b_runner_nospec "$D/.bisect-k2b_runner_nospec" > "$D/build-bisect-k2b.log" 2>&1 && echo "BUILD k2b ok" || { echo "BUILD k2b FAILED: $(grep -E 'FAILED|Hunk' "$D/build-bisect-k2b.log" | tail -2 | tr '\n' ' ')"; exit 1; }
bash $D/.stock_bisect_v2_lane0.sh qwen38-27b-rtx3090:stock028-k2b_runner_nospec k2b_runner_nospec
echo "K2B DONE $(date -u +%H:%M:%SZ)"
