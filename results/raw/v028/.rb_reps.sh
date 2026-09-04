#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
until grep -q "DIST GPU0 DONE" results/raw/v028/kvarn_split.out 2>/dev/null; do sleep 15; done
for r in 2 3; do bash results/raw/v028/.stock_bisect_v2_lane0.sh qwen38-27b-rtx3090:stock028-rb_mamba_state "rb_rep$r"; done
echo "RB REPS DONE $(date -u +%H:%M:%SZ)"
