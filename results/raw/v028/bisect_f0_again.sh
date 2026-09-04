#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
until grep -q "BISECT QUEUE DONE" results/raw/v028/bisect.out 2>/dev/null; do sleep 20; done
bash results/raw/v028/stock_bisect.sh qwen38-27b-rtx3090:pr43-swpad f0_fork_plainargs /app/venv/bin/vllm
echo "BISECT F0 DONE $(date -u +%H:%M:%SZ)"
