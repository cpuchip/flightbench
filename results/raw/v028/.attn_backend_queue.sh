#!/bin/bash
# Subsystem cut on stock 0.28.0 (+embed): the attention backend. 0.28.0 bumped vllm-flash-attn (2 cmake commits) and the
# FLASH_ATTN backend (4 commits); if the drift vanishes under TRITON_ATTN or FLASHINFER on this box, those commits are the diff to read.
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
until [ "$(grep -c "S5 DONE" results/raw/v028/launcher_bisect.out 2>/dev/null)" -ge 2 ]; do sleep 15; done
S=results/raw/v028/.stock_bisect_v2.sh
for r in 1 2; do bash $S qwen38-27b-rtx3090:stock028-embed "attn_triton_$r" vllm "--attention-backend TRITON_ATTN"; done
for r in 1 2; do bash $S qwen38-27b-rtx3090:stock028-embed "attn_flashinfer_$r" vllm "--attention-backend FLASHINFER"; done
echo "ATTN BACKEND DONE $(date -u +%H:%M:%SZ)"
