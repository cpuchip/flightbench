#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
S0=results/raw/v028/.stock_bisect_v2_lane0.sh
until grep -q "RUNNER SPLIT DONE" results/raw/v028/kvarn_split.out 2>/dev/null; do sleep 15; done
for r in 2 3; do bash $S0 qwen38-27b-rtx3090:stock028-k2b_runner_nospec "k2b_rep$r"; done
bash $S0 qwen38-27b-rtx3090:stock028-embed stock_rep2
echo "REPLICATES GPU0 DONE $(date -u +%H:%M:%SZ)"
