#!/bin/bash
# Main-branch regression arm in the record's cohort-harness shape (.cohort_sweep.sh): launcher run
# inside the container with its log tee'd to /tmp/server.log (the cohort client reads counters there),
# card 1 by UUID, fresh compile-cache volume per boot, OUR shipped default (DFLASH_TOKENS=7), key by
# env file (never on a command line). Container stays up so arms and the TTFT ladder run against it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
IMG=${IMG:-ghcr.io/syv-ai/qwen38-27b-rtx3090:latest}
NAME=${NAME:-qwen-main-test}
CARD=GPU-<fermion-card-1>
PORT=${PORT:-18021}
VOL=${VOL:-qwen-cache-maintest-$(date -u +%Y%m%d%H%M%S)}
MODELS='<workspace>\projects\qwen38-27b-rtx3090\models'
ENVFILE="$(cygpath -w "$HERE/maintest.env")"
docker rm -f "$NAME" >/dev/null 2>&1
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "device=$CARD" --ipc host --shm-size 64m \
  -p 127.0.0.1:$PORT:$PORT \
  -v "$VOL":/cache -v "$MODELS":/app/models \
  -e CUDA_VISIBLE_DEVICES=$CARD -e NVIDIA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT \
  -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 \
  -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
  -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 \
  --env-file "$ENVFILE" \
  --entrypoint bash "$IMG" -c '
    cd /app && echo "$VLLM_API_KEY" > api_key.txt
    export PATH=/app/venv/bin:$PATH
    exec bash single-user/start_qwen.sh 2>&1 | tee /tmp/server.log
  ' >/dev/null && echo "started $NAME on $CARD port $PORT cache $VOL image $IMG ($(date -u +%H:%M:%SZ))"
