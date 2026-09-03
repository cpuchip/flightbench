#!/bin/bash
# DFlash2 on KVarN on the 0.28 port: reproduce the maintainer's wrong-output cell and localize it with his own knob ladder.
# Reference = KVarN + MTP (character-exact per the maintainer) and KVarN + off. Each cell: greedy text probes -> jsonl.
until grep -q "CONNECTOR ARMS DONE" results/raw/v028/connector_arms.out 2>/dev/null; do sleep 30; done
IMG=qwen38-27b-rtx3090:pr43-0.28
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
cell () {  # lane name spec [extra -e ...]
  LANE=$1; NAME=$2; SPEC=$3; shift 3
  if [ "$LANE" = 0 ]; then CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020; else CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; fi
  export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=32768 -e DFLASH_MAX_LEN=32768 \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=huge -e SPEC=$SPEC -e PREFIX_CACHE=1 -e GPU_UTIL=0.93 -e MAX_SEQS=4 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "cd /app && echo \"\$VLLM_API_KEY\" > api_key.txt && exec bash single-user/start_qwen.sh" >/dev/null || { echo "LADDER $NAME: docker run failed"; return; }
  ok=0; for i in $(seq 1 90); do docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "LADDER $NAME: exited during boot: $(docker logs "$NAME" 2>&1 | grep -E 'ValueError|Error:|assert' | grep -v 'Engine core init' | tail -1 | cut -c1-160)"; break; }; [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { ok=1; break; }; sleep 10; done
  if [ $ok = 1 ]; then echo "LADDER $NAME serving ($SPEC $*): $(docker logs "$NAME" 2>&1 | grep -oE 'GPU KV cache size: [0-9,]+ tokens' | head -1)"; python "$OUTD/probe_text.py" "$OUTD/probes-$NAME.jsonl" 2>&1 | sed "s/^/LADDER $NAME/"; fi
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; echo "LADDER $NAME torn down $(date -u +%H:%M:%SZ)"
}
lane0 () { cell 0 l_mtp mtp; cell 0 l_off off; cell 0 l_df7 dflash2 -e DFLASH_TOKENS=7; cell 0 l_df15 dflash2 -e DFLASH_TOKENS=15; }
lane1 () { cell 1 l_df15_nofused dflash2 -e DFLASH_TOKENS=15 -e KVARN_FUSED_VERIFY=0; cell 1 l_df15_noadaptive dflash2 -e DFLASH_TOKENS=15 -e VLLM_DFLASH2_LOOKUP_ADAPTIVE=0; cell 1 l_df15_noprefix dflash2 -e DFLASH_TOKENS=15 -e PREFIX_CACHE=0; cell 1 l_df7_noprefix dflash2 -e DFLASH_TOKENS=7 -e PREFIX_CACHE=0; }
lane0 > "$OUTD/ladder.lane0.out" 2>&1 &
lane1 > "$OUTD/ladder.lane1.out" 2>&1 &
wait; cat "$OUTD/ladder.lane0.out" "$OUTD/ladder.lane1.out"
echo "== character-exact compare against the MTP cell =="; python - <<'PY'
import json, glob, os, sys
sys.stdout.reconfigure(encoding="utf-8")
def load(n):
    p = f"results/raw/v028/probes-{n}.jsonl"
    return {json.loads(l)["prompt_id"]: json.loads(l)["text"] for l in open(p, encoding="utf-8")} if os.path.exists(p) else None
ref = load("l_mtp")
for n in ("l_off", "l_df7", "l_df15", "l_df15_nofused", "l_df15_noadaptive", "l_df15_noprefix", "l_df7_noprefix"):
    d = load(n)
    if not ref or not d: print(f"  {n}: no rows"); continue
    same = [k for k in ref if d.get(k) == ref[k]]; diff = [k for k in ref if d.get(k) != ref[k]]
    print(f"  {n}: exact {len(same)}/{len(ref)}; differs on {diff}")
PY
echo "LADDER DONE $(date -u +%H:%M:%SZ)"
