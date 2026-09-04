#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
until grep -q "L2 AGAIN DONE" results/raw/v028/launcher_bisect.out 2>/dev/null; do sleep 15; done
S=results/raw/v028/.stock_bisect_v2.sh; IMG=qwen38-27b-rtx3090:pr43-swpad; E=/app/venv/bin/vllm
bash $S $IMG l3a_lmonly $E "--language-model-only"
bash $S $IMG l3b_noflashinfer_sampler $E "" "-e VLLM_USE_FLASHINFER_SAMPLER=0"
bash $S $IMG l3c_apiservers $E "--api-server-count 1"
echo "L3 SPLIT DONE $(date -u +%H:%M:%SZ)"
