#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
until grep -q "DIST GPU1 DONE" results/raw/v028/launcher_bisect.out 2>/dev/null; do sleep 15; done
for r in 1 2 3; do bash results/raw/v028/.stock_bisect_v2.sh qwen38-27b-rtx3090:stock028-s5_marlin "s5_marlin_$r"; done
echo "S5 DONE $(date -u +%H:%M:%SZ)"
