#!/bin/bash
# Phase 2 of the capping hunt, GPU 1, sequential. F0: the fork's fixed image under stock-style arguments (launcher cut).
# S1-S4: stock + embedding patch + one subset of the fork's regenerated 0.28 patches (patch-set cut). Each waits for its image.
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
bash results/raw/v028/stock_bisect.sh qwen38-27b-rtx3090:pr43-swpad f0_fork_plainargs /app/venv/bin/vllm
for s in s1_runner s2_mamba_align s3_hybrid_cg_promote s4_sampler_knobs; do
  until docker image inspect "qwen38-27b-rtx3090:stock028-$s" >/dev/null 2>&1 || grep -q "BUILD $s FAILED" results/raw/v028/build-bisect.log 2>/dev/null; do sleep 20; done
  docker image inspect "qwen38-27b-rtx3090:stock028-$s" >/dev/null 2>&1 && bash results/raw/v028/stock_bisect.sh "qwen38-27b-rtx3090:stock028-$s" "$s" || echo "BISECT $s skipped (no image)"
done
echo "BISECT QUEUE DONE $(date -u +%H:%M:%SZ)"
