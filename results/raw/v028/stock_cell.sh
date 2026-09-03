#!/bin/bash
# Stock vLLM 0.28.0 (docker.io/vllm/vllm-openai:v0.28.0), NO fork patches, the fork's own launcher arguments for the bf16
# drafter-free cell: the capping instrument (bf16 spec-off caps 9/12 turns on the port, 0-1 on 0.27.1). If stock caps, the
# regression is upstream; if not, it is in the fork's 0.28 patch set. Lane 1 (GPU 1), port 18025. The mission as everywhere else.
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
REPO='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-pr43'
OUTD="results/raw/v028"; TK=kv-probe-key; CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; NAME=stock_bf16_specoff
export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
docker rm -f "$NAME" >/dev/null 2>&1
MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT   -v "$MODELS":/app/models -v "$REPO":/app/repo:ro -e CUDA_VISIBLE_DEVICES=$CARD -e VLLM_API_KEY=$TK -e VLLM_NO_USAGE_STATS=1   --entrypoint vllm vllm/vllm-openai:v0.28.0 serve /app/models/Qwen3.8-27B-W4A16-AutoRound --served-model-name qwen3.8-27b   --chat-template /app/repo/chat_template-froggeric-v22.4.jinja --host 0.0.0.0 --port $PORT --gpu-memory-utilization 0.93   --max-model-len 57344 --max-num-seqs 4 --attention-backend FLASH_ATTN --kv-cache-dtype bfloat16 --mamba-ssm-cache-dtype float16   --max-num-batched-tokens 2048 --enable-prefix-caching --mamba-cache-mode align --reasoning-parser qwen3 --enable-prompt-tokens-details   --enable-auto-tool-choice --tool-call-parser qwen3_coder >/dev/null || { echo "STOCK docker run failed"; exit 1; }
ok=0; for i in $(seq 1 120); do docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "STOCK exited during boot: $(docker logs $NAME 2>&1 | grep -E 'Error|error:' | tail -2 | cut -c1-200)"; break; }; [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && { ok=1; break; }; sleep 10; done
if [ $ok = 1 ]; then
  echo "STOCK serving at ~$((i*10))s: $(docker logs $NAME 2>&1 | grep -oE 'GPU KV cache size: [0-9,]+ tokens' | head -1); marker=$(docker logs $NAME 2>&1 | grep -c 'Disabling fine-grained')"
  MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller OUT="$OUTD/mission-stock.jsonl" LABEL=stock028-bf16-specoff timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | sed "s/^/STOCK /" | cut -c1-300
  python - <<'PY'
import json, glob, os, sys; sys.stdout.reconfigure(encoding="utf-8")
fs = sorted(glob.glob("results/raw/v028/v6-stock028-bf16-specoff-*trace.jsonl"), key=os.path.getmtime)
if fs:
    rows = [json.loads(l) for l in open(fs[-1], encoding="utf-8")]; hdr = next(r for r in rows if r.get("kind") == "turns")
    reps = [r for r in rows if r.get("kind") == "reply"]; fin = [r.get("finish") for r in reps]; calls = list(hdr["turn_idx"].values())
    print(f"STOCK stock028-bf16-specoff: tool calls total {calls[-1]}, capped turns {fin.count('max_iters')}/12, length-cut turns {fin.count('length')}/12")
PY
fi
docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "STOCK DONE $(date -u +%H:%M:%SZ)"
