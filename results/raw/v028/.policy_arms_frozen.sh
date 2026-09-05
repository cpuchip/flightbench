#!/bin/bash
# PR 79's unmeasured claim, measured. The maintainer got 2.66 -> 2.79 tok/step by reversing
# dflash2-z-adaptive-emitted.patch, which feeds the block-length policy an emitted count that is
# too low, so the long block is entered less often. My claim in the PR: that is a tuning effect
# reached through a wrong number, and the honest knob is the policy's own. The policy's own knob
# for "fewer long blocks" that already exists is VLLM_DFLASH2_LOOKUP_STICKY (default 3): the
# coasting steps after a qualified entry. Three arms, cohort, field set in all three:
#   base     shipped patch,  STICKY=3
#   zrev     patch reversed, STICKY=3   (his arm)
#   sticky0  shipped patch,  STICKY=0   (the honest knob)
# Registered before the run: if zrev and sticky0 BOTH show lower round and higher tok/step than
# base, his gain is long-block occupancy and the honest knob reproduces it. If sticky0 lowers
# round but tok/step falls, long blocks were paying for themselves here and his gain was
# something else. Card 0, own cache volume so lane 1's runs cannot race it.
set -u
LOCK=/tmp/policy_arms.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020
VOL=qwen-cache-lane0; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/policy_client.py")
ZOLD_B64=$(base64 -w0 < "$SP/z_old.patch")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name  reverse_patch(0|1)  extra -e ...
  NAME=$1; REV=$2; shift 2
  if [ "$REV" = 1 ]; then PRE='echo "$ZOLD_B64" | base64 -d > /tmp/z_old.patch; cd /app/venv/lib/python3.12/site-packages/vllm && patch -p1 -R -s < /tmp/z_old.patch && echo "Z-PATCH REVERSED" || { echo "REVERSE FAILED"; exit 97; }; cd /app; '; else PRE=''; fi
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=15 -e PREFIX_CACHE=1 \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 \
    -e CLIENT_B64="$CLIENT_B64" -e ZOLD_B64="$ZOLD_B64" "$@" \
    --entrypoint bash "$IMG" -c "$FIELD $PRE"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      grep -c "draft_sample_method" single-user/start_qwen.sh | sed "s/^/FIELD_LINES=/"
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; tail -15 /tmp/server.log; exit 1; }
      grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1
      echo "STICKY=${VLLM_DFLASH2_LOOKUP_STICKY:-default}"
      echo "$CLIENT_B64" | base64 -d > /tmp/policy_client.py
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/policy_client.py
    ' > "$OUTD/policy-$NAME.txt" 2>&1
  echo "POLICY $NAME exit=$? $(grep -aE 'draft_logits|STICKY=|Z-PATCH|REVERSE FAILED|NO HEALTH|FIELD_LINES' "$OUTD/policy-$NAME.txt" | tr '\n' ' ')"
  echo "POLICY $NAME rows=$(grep -ac '^ROW ' "$OUTD/policy-$NAME.txt")"
}
arm pol-base    0
arm pol-zrev    1
arm pol-sticky0 0 -e VLLM_DFLASH2_LOOKUP_STICKY=0
echo "POLICY ARMS DONE $(date -u +%H:%M:%SZ)"
