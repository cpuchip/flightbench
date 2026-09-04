#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
S=results/raw/v028/.stock_bisect_v2.sh; IMG=qwen38-27b-rtx3090:pr43-swpad; E=/app/venv/bin/vllm
until grep -q "L3 SPLIT DONE" results/raw/v028/launcher_bisect.out 2>/dev/null; do sleep 15; done
for r in 2 3; do bash $S $IMG "l3_group_rep$r" $E "--language-model-only --api-server-count 1" "-e VLLM_USE_FLASHINFER_SAMPLER=0"; done
bash $S $IMG f0_plain_rep2 $E
echo "REPLICATES GPU1 DONE $(date -u +%H:%M:%SZ)"
