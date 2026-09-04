#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
S=results/raw/v028/.stock_bisect_v2.sh; IMG=qwen38-27b-rtx3090:pr43-swpad; E=/app/venv/bin/vllm
bash $S $IMG l1_async $E "--async-scheduling"
bash $S $IMG l2_compile $E '--compilation-config {"custom_ops":["+rms_norm","+silu_and_mul"],"max_cudagraph_capture_size":32}'
bash $S $IMG l3_lmonly_sampler $E "--language-model-only --api-server-count 1" "-e VLLM_USE_FLASHINFER_SAMPLER=0"
echo "LAUNCHER QUEUE DONE $(date -u +%H:%M:%SZ)"
