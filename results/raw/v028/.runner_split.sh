#!/bin/bash
cd /c/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench || exit 1
D=results/raw/v028
for g in ra_hash_geometry rb_mamba_state rc_model_runner rd_attn_dflash; do docker build -t "qwen38-27b-rtx3090:stock028-$g" "$D/.bisect-$g" > "$D/build-bisect-$g.log" 2>&1 && echo "BUILD $g ok" || echo "BUILD $g FAILED: $(grep -E 'FAILED|Hunk' "$D/build-bisect-$g.log" | tail -1)"; done
until grep -q "L3 LANE0 DONE" results/raw/v028/kvarn_split.out 2>/dev/null; do sleep 15; done
for g in ra_hash_geometry rb_mamba_state rc_model_runner rd_attn_dflash; do docker image inspect "qwen38-27b-rtx3090:stock028-$g" >/dev/null 2>&1 && bash $D/.stock_bisect_v2_lane0.sh "qwen38-27b-rtx3090:stock028-$g" "$g"; done
echo "RUNNER SPLIT DONE $(date -u +%H:%M:%SZ)"
