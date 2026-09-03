#!/bin/bash
# Fix test for KVarN + DFlash2 on the 0.28 port. The collapse survives PREFIX_CACHE=0, so it is not the continuation path.
# The rebased #43 (910bbf2, 'long verify split') drops the 'NQ * Hk <= sm_count' condition from KVarN's verify auto-split; the
# installed kernel already warns the one-stage kernel 'can return finite but incorrect logits' at long context on sm86. Cells:
# the mission with that one-line change (lane 0); the maintainer's residue sweep unpatched, then patched (lane 1); then round four.
until grep -q "LADDER DONE" results/raw/v028/ladder.out 2>/dev/null; do sleep 30; done
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
mcell () {  # lane name label launcher ctx spec [extra -e ...]: one mission run, thinking off; reports capped turns. PATCHFILE (host path) applied at boot if set.
  LANE=$1; NAME=$2; LABEL=$3; LAUNCH=$4; CTX=$5; SPEC=$6; shift 6
  if [ "$LANE" = 0 ]; then CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020; else CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; fi
  export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
  docker rm -f "$NAME" >/dev/null 2>&1
  if [ -n "${PATCHFILE:-}" ]; then PV=(-v "$PATCHFILE:/tmp/p.patch:ro"); CMD='cd /app/venv/lib/python3.12/site-packages/vllm && { patch -p1 -N < /tmp/p.patch || { echo PATCH-FAILED; exit 97; }; } && cd /app && echo "$VLLM_API_KEY" > api_key.txt && exec bash single-user/'"$LAUNCH"; else PV=(); CMD='cd /app && echo "$VLLM_API_KEY" > api_key.txt && exec bash single-user/'"$LAUNCH"; fi
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models "${PV[@]}" \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=57344 -e DFLASH_MAX_LEN=57344 \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=$CTX -e SPEC=$SPEC -e PREFIX_CACHE=1 -e GPU_UTIL=0.93 -e MAX_SEQS=4 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "$CMD" >/dev/null || { echo "LADDER $NAME: docker run failed"; return; }
  ok=0; for i in $(seq 1 90); do docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "LADDER $NAME: exited during boot: $(docker logs "$NAME" 2>&1 | grep -E 'PATCH-FAILED|Hunk|Error' | tail -2 | cut -c1-120)"; break; }; [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { ok=1; break; }; sleep 10; done
  if [ $ok = 1 ]; then
    echo "LADDER $NAME serving ($LAUNCH $CTX $SPEC $* patch=${PATCHFILE:+yes})"
    MODEL=qwen3.8-27b THINK=off MAXTOK=900 SEAT=controller OUT="$OUTD/mission-v028-diag.jsonl" LABEL="$LABEL" timeout 2400 python benches/mission.py 2>&1 | grep -E "=== V6|Traceback|Error" | sed "s/^/LADDER $NAME /" | cut -c1-260
    python - "$LABEL" <<'PY'
import json, glob, os, sys; sys.stdout.reconfigure(encoding="utf-8")
lab = sys.argv[1]; fs = sorted(glob.glob(f"results/raw/v028/v6-{lab}-*trace.jsonl"), key=os.path.getmtime)
if fs:
    rows = [json.loads(l) for l in open(fs[-1], encoding="utf-8")]; hdr = next(r for r in rows if r.get("kind") == "turns")
    reps = [r for r in rows if r.get("kind") == "reply"]; fin = [r.get("finish") for r in reps]; calls = list(hdr["turn_idx"].values())
    t2 = str(reps[1].get("text") or "") if len(reps) > 1 else ""
    print(f"LADDER {lab}: tool calls total {calls[-1]}, capped turns {fin.count('max_iters')}/12, length-cut turns {fin.count('length')}/12, turn2 head {t2[:60]!r}")
PY
  fi
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; echo "LADDER $NAME debug lines: $(grep -c 'KVARN_CONTINUATION' "$OUTD/server-$NAME.log") patch lines: $(grep -cE 'patching file|Hunk' "$OUTD/server-$NAME.log")"; docker rm -f "$NAME" >/dev/null 2>&1; echo "LADDER $NAME torn down $(date -u +%H:%M:%SZ)"
}
scell () {  # lane name label launcher ctx spec [extra -e ...]: boot, then the maintainer's residue sweep (all 128 residues) inside the container. PATCHFILE as in mcell.
  LANE=$1; NAME=$2; LABEL=$3; LAUNCH=$4; CTX=$5; SPEC=$6; shift 6
  if [ "$LANE" = 0 ]; then CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020; else CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18025; fi
  export BASE=http://127.0.0.1:$PORT/v1 KEY=$TK
  docker rm -f "$NAME" >/dev/null 2>&1
  if [ -n "${PATCHFILE:-}" ]; then PV=(-v "$PATCHFILE:/tmp/p.patch:ro"); CMD='cd /app/venv/lib/python3.12/site-packages/vllm && { patch -p1 -N < /tmp/p.patch || { echo PATCH-FAILED; exit 97; }; } && cd /app && echo "$VLLM_API_KEY" > api_key.txt && exec bash single-user/'"$LAUNCH"; else PV=(); CMD='cd /app && echo "$VLLM_API_KEY" > api_key.txt && exec bash single-user/'"$LAUNCH"; fi
  MSYS_NO_PATHCONV=1 docker run -d --name "$NAME" --gpus "\"device=$CARD\"" --ipc host -p 127.0.0.1:$PORT:$PORT \
    -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$MODELS":/app/models -v "$MODELS\Qwen3.8-27B-W4A16-AutoRound-fast":/app/models/Qwen3.8-27B-W4A16-AutoRound-fast:ro -v "$CORPUSF":/tmp/labd_corpus.txt:ro "${PV[@]}" \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e PORT=$PORT -e VLLM_API_KEY=$TK -e MAX_LEN=57344 -e DFLASH_MAX_LEN=57344 \
    -e MODEL=models/Qwen3.8-27B-W4A16-AutoRound -e CTX=$CTX -e SPEC=$SPEC -e PREFIX_CACHE=1 -e GPU_UTIL=0.93 -e MAX_SEQS=4 \
    -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e VLLM_OFFLOAD_KEEP_SHM=1 -e VLLM_DISABLE_COMPILE_CACHE=1 "$@" \
    --entrypoint bash "$IMG" -c "$CMD" >/dev/null || { echo "LADDER $NAME: docker run failed"; return; }
  ok=0; for i in $(seq 1 90); do docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { echo "LADDER $NAME: exited during boot: $(docker logs "$NAME" 2>&1 | grep -E 'PATCH-FAILED|Hunk|Error' | tail -2 | cut -c1-120)"; break; }; [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TK" http://127.0.0.1:$PORT/health)" = 200 ] && docker logs "$NAME" 2>&1 | grep -q 'GPU KV cache size' && { ok=1; break; }; sleep 10; done
  if [ $ok = 1 ]; then
    echo "LADDER $NAME serving ($LAUNCH $CTX $SPEC $* patch=${PATCHFILE:+yes}) sweep start $(date -u +%H:%M:%SZ)"
    docker exec -e PORT=$PORT -e VLLM_API_KEY=$TK -e CORPUS=/tmp/labd_corpus.txt "$NAME" bash -c "cd /app && venv/bin/python bench/residue_sweep.py $LABEL 0 128" > "$OUTD/sweep-$NAME.out" 2>&1
    echo "LADDER $NAME sweep: $(grep -c '] BROKEN' "$OUTD/sweep-$NAME.out") broken lines; $(grep -E 'neighbourhood|DONE|Traceback|Error' "$OUTD/sweep-$NAME.out" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  fi
  docker logs "$NAME" > "$OUTD/server-$NAME.log" 2>&1; echo "LADDER $NAME debug lines: $(grep -c 'KVARN_CONTINUATION' "$OUTD/server-$NAME.log") patch lines: $(grep -cE 'patching file|Hunk' "$OUTD/server-$NAME.log")"; docker rm -f "$NAME" >/dev/null 2>&1; echo "LADDER $NAME torn down $(date -u +%H:%M:%SZ)"
}
CORPUSF="$(cygpath -w "$PWD/results/raw/v028/labd_corpus.txt")"
LV="$(cygpath -w "$PWD/results/raw/v028/.longverify.patch")"
R4='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-pr43\patches\kvarn-continuation-flushed-blocks.draft.patch'
R34='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\flightbench\results\raw\v028\.r3r4.patch'
lane0 () {
  PATCHFILE=$LV mcell 0 k_df7_longverify v028-kvarn-df7-longverify start_qwen.sh huge dflash2
  PATCHFILE=$LV mcell 0 k_df7_longverify_b v028-kvarn-df7-longverify-b start_qwen.sh huge dflash2
  PATCHFILE=$R4 mcell 0 k_df7_r4 v028-kvarn-df7-r4 start_qwen.sh huge dflash2 -e KVARN_CONTINUATION_DEBUG=1
}
lane1 () {
  scell 1 k_df7_sweep sweep-v028-kvarn-df7 start_qwen.sh huge dflash2
  PATCHFILE=$LV scell 1 k_df7_sweep_lv sweep-v028-kvarn-df7-longverify start_qwen.sh huge dflash2
  PATCHFILE=$R34 mcell 1 k_df7_r3r4 v028-kvarn-df7-r3r4 start_qwen.sh huge dflash2 -e KVARN_CONTINUATION_DEBUG=1
}
lane0 > "$OUTD/fixtest.lane0.out" 2>&1 &
lane1 > "$OUTD/fixtest.lane1.out" 2>&1 &
wait; cat "$OUTD/fixtest.lane0.out" "$OUTD/fixtest.lane1.out"
echo "PATCHTEST DONE $(date -u +%H:%M:%SZ)"
