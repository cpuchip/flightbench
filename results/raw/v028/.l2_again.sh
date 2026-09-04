#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
until grep -q "LAUNCHER QUEUE DONE" results/raw/v028/launcher_bisect.out 2>/dev/null; do sleep 15; done
bash results/raw/v028/.stock_bisect_v2.sh qwen38-27b-rtx3090:pr43-swpad l2_compile /app/venv/bin/vllm "--compilation-config '{\"custom_ops\":[\"+rms_norm\",\"+silu_and_mul\"],\"max_cudagraph_capture_size\":32}'"
echo "L2 AGAIN DONE $(date -u +%H:%M:%SZ)"
