#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
for s in s1_runner s2_mamba_align s3_hybrid_cg_promote s4_sampler_knobs; do
  bash results/raw/v028/.stock_bisect_frozen.sh "qwen38-27b-rtx3090:stock028-$s" "$s"
done
bash results/raw/v028/.stock_bisect_frozen.sh qwen38-27b-rtx3090:pr43-swpad f0_fork_plainargs /app/venv/bin/vllm
echo "BISECT QUEUE2 DONE $(date -u +%H:%M:%SZ)"
