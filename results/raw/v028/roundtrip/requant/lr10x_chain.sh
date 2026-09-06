#!/bin/bash
# Card 1, after the seeds58 arms: one more epoch of the warm-start fine-tune at TEN TIMES the learning rate (2e-4),
# same data (the 2,000 captured records in /work/hs), same config otherwise; export; verify; serve on two seed sets at
# the fitting profile against the shipped head (bl7p3 for seeds 1-4, shipped58 for seeds 5-8). The question: does a
# larger step move the head at all, given that lr 2e-5 moved weights by 0.4 percent of one int4 step and measured
# nothing across two seed sets. Everything logged under specforge-roundtrip/logs/*lr10x*.
set -u
export MSYS_NO_PATHCONV=1
SP=<home>/AppData/Local/Temp/claude/<workspace-slug>/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad
RT="$SP/specforge-roundtrip"; PR="$SP/specforge-probe"
RTW=$(cygpath -w "$RT"); PRW=$(cygpath -w "$PR")
MODELS='<workspace>\projects\qwen38-27b-rtx3090\models'
GPU=GPU-<fermion-card-1>
IMG=qwen38-27b-rtx3090:pr43-6869c80
while docker ps --format '{{.Names}}' | grep -qx seeds58; do sleep 20; done
sleep 15
docker rm -f lr10x >/dev/null 2>&1
docker run -d --rm --name lr10x \
  --gpus "\"device=$GPU\"" --ipc host \
  -e NVIDIA_VISIBLE_DEVICES=$GPU -e CUDA_VISIBLE_DEVICES=$GPU \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False \
  -e PATH=/app/venv/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -v "$MODELS":/app/models -v "$RTW":/work -v "$PRW":/probe:ro -v qwen-cache-lane1:/cache \
  --entrypoint bash "$IMG" -c '
L=/work/logs/lr10x.log
stamp() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> $L; }
export TOKENIZERS_PARALLELISM=false HOME=/cache
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) LR10X START torch_devices=$(python -c "import torch;print(torch.cuda.device_count())")" > $L
(apt-get install -y -qq git >>/work/logs/setup-lr10x.log 2>&1 || (apt-get update -qq >>/work/logs/setup-lr10x.log 2>&1 && apt-get install -y -qq git >>/work/logs/setup-lr10x.log 2>&1))
cd /work/SpecForge && pip install -q -e . --no-deps >>/work/logs/setup-lr10x.log 2>&1
pip install -q accelerate --no-deps >>/work/logs/setup-lr10x.log 2>&1
cd /work
stamp "stage 2: train, lr 2e-4 (10x the round trip), 250 steps, same data and config otherwise"
specforge train -c /work/roundtrip.yaml data.hidden_states_path=/work/hs data.cache_dir=/work/cache run_id=lr10x output_dir=/work/outputs/lr10x training.max_steps=250 training.learning_rate=2.0e-4 2>&1 | while IFS= read -r line; do printf "%s %s\n" "$(date -u +%H:%M:%S)" "$line"; done > /work/logs/train-lr10x.log
stamp "train done; steps logged: $(grep -c " step [0-9]*: {" /work/logs/train-lr10x.log)"
python /work/train_summary.py /work/logs/train-lr10x.log /work/logs/train_steps-lr10x.csv >> $L 2>&1
CKPT=$(ls -d /work/outputs/lr10x/*step*/ 2>/dev/null | tail -1)
if [ -z "$CKPT" ] || [ ! -f "$CKPT/training_state.pt" ]; then stamp "NO CHECKPOINT; abort"; tail -20 /work/logs/train-lr10x.log >> $L; exit 2; fi
stamp "stage 3: export $CKPT"
specforge export --to hf --checkpoint "$CKPT" --draft-config /probe/head_bf16/config.json --output-dir /work/export/head-ft-lr10x > /work/logs/export-lr10x.log 2>&1
stamp "export rc=$?"
python /work/verify_export.py /work/export/head-ft-lr10x /probe/head_bf16 /app/models/Qwen3.8-27B-DFlash2-W4A16 > /work/logs/verify_export-lr10x.log 2>&1
stamp "verify rc=$? $(grep -E "^(overall|VERIFY|FATAL|names/shapes)" /work/logs/verify_export-lr10x.log | head -3 | tr "\n" " ")"
for A in ft10xs14:1,2,3,4 ft10xs58:5,6,7,8; do
  arm=${A%%:*}; seeds=${A#*:}
  stamp "ARM $arm start"
  VLLM_API_KEY=k$RANDOM$RANDOM bash /work/serve_arm.sh $arm /work/export/head-ft-lr10x 3000000000 /work/logs/serve-$arm.txt $seeds
  stamp "ARM $arm rc=$? rows=$(grep -c "^ROW " /work/logs/serve-$arm.txt)"
done
stamp "SUMMARY seeds 1-4 (baseline bl7p3)"
python /work/summarize_serve.py /work/baseline/drf-bl7p3.txt /work/logs/serve-ft10xs14.txt >> $L 2>&1
stamp "SUMMARY seeds 5-8 (baseline shipped58)"
python /work/summarize_serve.py /work/logs/serve-shipped58.txt /work/logs/serve-ft10xs58.txt >> $L 2>&1
stamp "LR10X DONE"
'
echo "launched lr10x $(date -u +%H:%M:%SZ)"
