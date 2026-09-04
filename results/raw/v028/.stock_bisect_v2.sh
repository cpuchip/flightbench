#!/bin/bash
# Bisect cell: IMG LABEL [ENTRY]. Stock-style serve arguments (no fork launcher knobs), bf16, spec off, prefix caching on.
# Originally: stock vLLM 0.28.0 plus ONLY the embedding patch the checkpoint needs to load (stock cannot read AutoRound packed embeddings), the fork's own launcher arguments for the bf16
# drafter-free cell: the capping instrument (bf16 spec-off caps 9/12 turns on the port, 0-1 on 0.27.1). If stock caps, the
# regression is upstream; if not, it is in the fork's 0.28 patch set. Lane 1 (GPU 1), port 18025. The mission as everywhere else.
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
REPO='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-pr43'
IMG=${1:?image}; LABEL=${2:?label}; ENTRY=${3:-vllm}; EXTRA="${4:-}"; ENVS="${5:-}"; OUTD="results/raw/v028"; TK=kv-probe-key; CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; NAME=bis_$LABEL
export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
docker rm -f "$NAME" >/dev/null 2>&1
SERVE_ARGS="/app/models/Qwen3.8-27B-W4A16-AutoRound --attention-backend FLASH_ATTN --served-model-name qwen3.8-27b --chat-template /app/repo/chat_template-froggeric-v22.4.jinja --host 0.0.0.0 --port $PORT --gpu-memory-utilization 0.93 --max-model-len 57344 --max-num-seqs 4 --kv-cache-dtype bfloat16 --mamba-ssm-cache-dtype float16 --max-num-batched-tokens 2048 --enable-prefix-caching --mamba-cache-mode align --reasoning-parser qwen3 --enable-prompt-tokens-details --enable-auto-tool-choice --tool-call-parser qwen3_coder $EXTRA"
case "$ENTRY" in
  */*) IMGCMD=(--entrypoint bash "$IMG" -c "export PATH=$(dirname "$ENTRY"):\$PATH; cd /app; exec vllm serve $SERVE_ARGS");;
  *)   IMGCMD=(--entrypoint "$ENTRY" "$IMG" serve $SERVE_ARGS);;
esac
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT   -v "$MODELS":/app/models -v "$REPO":/app/repo:ro -e CUDA_VISIBLE_DEVICES=$CARD -e VLLM_API_KEY=$TK -e VLLM_NO_USAGE_STATS=1 $ENVS   "${IMGCMD[@]}" >/dev/null || { echo "BISECT $LABEL docker run failed"; exit 1; }
ok=0; for i in $(seq 1 120); do docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "BISECT $LABEL exited during boot: $(docker logs $NAME 2>&1 | grep -E 'Error|error:' | tail -2 | cut -c1-200)"; break; }; [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && { ok=1; break; }; sleep 10; done
if [ $ok = 1 ]; then
  echo "BISECT $LABEL serving at ~$((i*10))s: $(docker logs $NAME 2>&1 | grep -oE 'GPU KV cache size: [0-9,]+ tokens' | head -1); marker=$(docker logs $NAME 2>&1 | grep -c 'Disabling fine-grained')"
  MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller OUT="$OUTD/mission-bisect.jsonl" LABEL="bis-$LABEL" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | sed "s/^/BISECT $LABEL /" | cut -c1-300
  python - "$LABEL" <<'PY'
import json, glob, os, sys; sys.stdout.reconfigure(encoding="utf-8")
fs = sorted(glob.glob(f"results/raw/v028/v6-bis-{sys.argv[1]}-*trace.jsonl"), key=os.path.getmtime)
if fs:
    rows = [json.loads(l) for l in open(fs[-1], encoding="utf-8")]; hdr = next(r for r in rows if r.get("kind") == "turns")
    reps = [r for r in rows if r.get("kind") == "reply"]; fin = [r.get("finish") for r in reps]; calls = list(hdr["turn_idx"].values())
    print(f"BISECT {sys.argv[1]}: tool calls total {calls[-1]}, capped turns {fin.count('max_iters')}/12, length-cut turns {fin.count('length')}/12")
PY
fi
docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "BISECT $LABEL DONE $(date -u +%H:%M:%SZ)"
