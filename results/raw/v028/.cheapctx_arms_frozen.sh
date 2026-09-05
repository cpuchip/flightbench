#!/bin/bash
# ARM 2: the dead branch with a documented gain. VLLM_DFLASH2_LOOKUP_CHEAP_CTX defaults to "0", so
#   if self.draft_max_seq_len <= self._lookup_cheap_ctx: return self.num_speculative_steps
# never fires. The source comment claims taking the long block unconditionally below the threshold
# wins "+8% at C1" because an extra verify position is nearly free at short context ("+6% per step
# at 1.5k against +27% at 25k"). Four arms: 0 (control), 4096, 8192, 16384. Field set. Registered
# before the run: tok/step rises on prompts whose context stays under the threshold, decode tok/s
# rises with it, and the gain shrinks or reverses at the highest threshold where the extra
# positions cost more than they return. Falsifier: no tok_s gain at any threshold means the +8%
# does not reproduce on this box. Card 1, own cache volume.
set -u
LOCK=/tmp/cheapctx_arms.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18021
VOL=qwen-cache-lane1; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name cheap_ctx
  NAME=$1; CC=$2
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=15 -e PREFIX_CACHE=1 -e VLLM_DFLASH2_LOOKUP_CHEAP_CTX=$CC \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
    --entrypoint bash "$IMG" -c "$FIELD"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; tail -15 /tmp/server.log; exit 1; }
      echo "RESOLVED $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) CHEAP_CTX=${VLLM_DFLASH2_LOOKUP_CHEAP_CTX} $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/cheapctx-$NAME.txt" 2>&1
  echo "CHEAPCTX $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH' "$OUTD/cheapctx-$NAME.txt" | head -2 | tr '\n' ' ')"
  echo "CHEAPCTX $NAME rows=$(grep -ac '^ROW ' "$OUTD/cheapctx-$NAME.txt")"
}
arm cc0     0
arm cc4096  4096
arm cc8192  8192
arm cc16384 16384
echo "CHEAPCTX ARMS DONE $(date -u +%H:%M:%SZ)"
