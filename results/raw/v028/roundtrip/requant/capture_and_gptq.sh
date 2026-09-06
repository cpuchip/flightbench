#!/bin/bash
# GPTQ requantization of the fine-tuned DFlash2 head with the fork's own pipeline (drafter/README.md, "To rebuild it"):
# 1. Hessians from the drafter's OWN inputs: vLLM in-process, eager, the bf16 fine-tuned head speculating on 400 prompts
#    (the unused tail of the training prompt file, chat-templated, 45% thinking) at model-default sampling, target = the
#    -fast W4A16 variant the launcher serves. 2. quant_dflash2.py GPTQ int4 g128 -> compressed-tensors. Card 1 by UUID.
set -u
export MSYS_NO_PATHCONV=1
SP=<home>/AppData/Local/Temp/claude/<workspace-slug>/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad
R="$SP/requant"
M='<workspace>\projects\qwen38-27b-rtx3090\models'
U=GPU-<fermion-card-1>
docker rm -f requant-capture >/dev/null 2>&1
docker run -d --rm --name requant-capture --gpus "\"device=$U\"" --ipc host -e NVIDIA_VISIBLE_DEVICES=$U -e CUDA_VISIBLE_DEVICES=$U \
  -v "$M":/app/models -v "$R":/mnt/requant -v qwen-cache-lane1:/cache --entrypoint bash qwen38-27b-rtx3090:pr43-6869c80 -c '
cd /app && export PATH=/app/venv/bin:$PATH HOME=/cache
L=/mnt/requant/capture.log
echo "$(date -u +%H:%M:%SZ) CAPTURE START torch_devices=$(python -c "import torch;print(torch.cuda.device_count())")" > $L
MODEL=/app/models/Qwen3.8-27B-W4A16-AutoRound-fast DRAFT=/app/models/Qwen3.8-27B-DFlash2-ft-roundtrip-2026-09-06 \
  OUT=/mnt/requant/drafter/runs/dflash2-ft GPU_UTIL=0.92 \
  python /mnt/requant/drafter/capture_dflash2.py --prompts 400 --max-tokens 384 --rows 250000 >> $L 2>&1
echo "$(date -u +%H:%M:%SZ) CAPTURE rc=$? hessians=$(ls -la /mnt/requant/drafter/runs/dflash2-ft/hessians.pt 2>&1 | cut -c1-80)" >> $L
if [ -f /mnt/requant/drafter/runs/dflash2-ft/hessians.pt ]; then
  echo "$(date -u +%H:%M:%SZ) GPTQ START" >> $L
  python /mnt/requant/drafter/quant_dflash2.py /app/models/Qwen3.8-27B-DFlash2-ft-roundtrip-2026-09-06 /app/models/Qwen3.8-27B-DFlash2-ft-W4A16-gptq-2026-09-06 /mnt/requant/drafter/runs/dflash2-ft/hessians.pt >> $L 2>&1
  echo "$(date -u +%H:%M:%SZ) GPTQ rc=$?" >> $L
fi
echo "$(date -u +%H:%M:%SZ) CAPTURE_AND_GPTQ DONE" >> $L
'
echo "launched requant-capture $(date -u +%H:%M:%SZ)"
