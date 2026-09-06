#!/bin/bash
# Card 0, after the soak container is gone: three arms at the SHIPPED profile (the launcher defaults the soak ran:
# 5.2 GiB pin, 65536, lookup on, GPU_UTIL 0.90). Two are the instrument's noise floor (the shipped head on seed sets
# 9-12 and 13-16, to sit beside the soak's seeds 1-4 and card 1's seeds 5-8), the third is the RTN-requantized
# untrained head on seeds 1-4, paired against the soak's pass-1 rows. Logs under specforge-roundtrip/logs/.
set -u
export MSYS_NO_PATHCONV=1
SP=<home>/AppData/Local/Temp/claude/<workspace-slug>/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad
RT="$SP/specforge-roundtrip"; RTW=$(cygpath -w "$RT")
MODELS='<workspace>\projects\qwen38-27b-rtx3090\models'
IMG=qwen38-27b-rtx3090:pr43-6869c80
while docker ps --format '{{.Names}}' | grep -qx soak; do sleep 20; done
sleep 30
used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i 0 | tr -d ' ')
if [ "${used:-9999}" -ge 500 ]; then echo "REFUSING: card 0 busy (${used} MiB) $(date -u +%H:%M:%SZ)"; exit 3; fi
docker rm -f card0-arms >/dev/null 2>&1
docker run -d --rm --name card0-arms --gpus '"device=0"' --ipc host \
  -e CUDA_VISIBLE_DEVICES=0 -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False \
  -v "$MODELS":/app/models -v "$RTW":/work -v qwen-cache-lane0:/cache \
  --entrypoint bash "$IMG" -c '
L=/work/logs/card0-arms.log
stamp() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> $L; }
export PATH=/app/venv/bin:$PATH HOME=/cache
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) CARD0 ARMS START torch_devices=$(python -c "import torch;print(torch.cuda.device_count())")" > $L
for A in shippedS912:Qwen3.8-27B-DFlash2-W4A16:9,10,11,12 shippedS1316:Qwen3.8-27B-DFlash2-W4A16:13,14,15,16 ctlrtnS14:Qwen3.8-27B-DFlash2-ctl-W4A16-rtn-2026-09-06:1,2,3,4; do
  arm=${A%%:*}; rest=${A#*:}; d=${rest%%:*}; seeds=${rest#*:}
  stamp "ARM $arm DRAFT=$d SEEDS=$seeds start"
  VLLM_API_KEY=k$RANDOM$RANDOM bash /work/serve_arm_shipped.sh $arm /app/models/$d 0 /work/logs/serve-$arm.txt $seeds
  stamp "ARM $arm rc=$? rows=$(grep -c "^ROW " /work/logs/serve-$arm.txt)"
done
stamp "SUMMARY noise floor (each arm against itself, for its own mean)"
for a in shippedS912 shippedS1316; do python /work/summarize_serve.py /work/logs/serve-$a.txt /work/logs/serve-$a.txt >> $L 2>&1; done
stamp "SUMMARY RTN untrained head, shipped profile, vs the soak pass-1 rows"
python /work/summarize_serve.py /work/baseline/soak-p1-shipped-profile.txt /work/logs/serve-ctlrtnS14.txt >> $L 2>&1
stamp "CARD0 ARMS DONE"
'
echo "launched card0-arms $(date -u +%H:%M:%SZ)"
