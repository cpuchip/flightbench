#!/bin/bash
# The regression harness's arm launcher (maintest/launch-main-arm.sh) with a patch list applied to the
# installed tree before the launcher runs, and the fork's verify.sh gate run first (its result is in the
# server log). usage: PATCHES="a.patch b.patch" NAME=qwen-fix-test bash launch-fix-arm.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; MT="$HERE/../maintest"
IMG=${IMG:-qwen38-27b-rtx3090:main-7ca84fc}
NAME=${NAME:-qwen-fix-test}
CARD=GPU-<card-1-uuid>
PORT=${PORT:-18021}
VOL=${VOL:-qwen-cache-fixtest-$(date -u +%Y%m%d%H%M%S)}
MODELS='<workspace>\projects\qwen38-27b-rtx3090\models'
ENVFILE="$(cygpath -w "$MT/maintest.env")"
FIXW="$(cygpath -w "$HERE")"
PATCHES=${PATCHES:?list the patch files in out/ to apply}
docker rm -f "$NAME" >/dev/null 2>&1
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "device=$CARD" --ipc host --shm-size 64m \
  -p 127.0.0.1:$PORT:$PORT \
  -v "$VOL":/cache -v "$MODELS":/app/models -v "$FIXW":/fix \
  -e CUDA_VISIBLE_DEVICES=$CARD -e NVIDIA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT \
  -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=7 -e PREFIX_CACHE=1 \
  -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
  -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 \
  -e PATCHES="$PATCHES" \
  --env-file "$ENVFILE" \
  --entrypoint bash "$IMG" -c '
    SP=/app/venv/lib/python3.12/site-packages/vllm
    for p in $PATCHES; do (cd $SP && patch -p1 -N -s < /fix/out/$p) && echo "PATCH applied $p" || { echo "PATCH FAILED $p"; exit 2; }; done
    cd /app && echo "$VLLM_API_KEY" > api_key.txt
    export PATH=/app/venv/bin:$PATH
    bash verify.sh --no-server 2>&1 | grep -E "^verify:|FAIL" | sed "s/^/GATE /"
    exec bash single-user/start_qwen.sh 2>&1 | tee /tmp/server.log
  ' >/dev/null && echo "started $NAME on $CARD port $PORT cache $VOL image $IMG patches=[$PATCHES] ($(date -u +%H:%M:%SZ))"
