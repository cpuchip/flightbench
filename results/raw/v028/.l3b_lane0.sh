#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
until grep -q "K2B DONE" results/raw/v028/kvarn_split.out 2>/dev/null; do sleep 15; done
bash results/raw/v028/.stock_bisect_v2_lane0.sh qwen38-27b-rtx3090:pr43-swpad l3b0_noflashinfer_sampler /app/venv/bin/vllm "" "-e VLLM_USE_FLASHINFER_SAMPLER=0"
bash results/raw/v028/.stock_bisect_v2_lane0.sh qwen38-27b-rtx3090:pr43-swpad l3a0_lmonly /app/venv/bin/vllm "--language-model-only"
echo "L3 LANE0 DONE $(date -u +%H:%M:%SZ)"
