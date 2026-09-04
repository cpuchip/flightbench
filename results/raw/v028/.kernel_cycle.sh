#!/bin/bash
# Kernel pin cycle. A persisted cache is a pin: force one GDN kernel's autotune winner at a time and boot with the cache.
# GOOD tree (both config, 67/1): force each of the three differing kernels to the bad draw's choice. BAD tree (cache-on
# config, 144/7): force each to the good draw's choice. One boot each; restore the tree between cells.
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
    echo "LADDER $NAME serving ($LAUNCH $CTX $SPEC $* patch=${PATCHFILE:+yes}) marker=$(docker logs "$NAME" 2>&1 | grep -c 'Disabling fine-grained') blocks=$(docker logs "$NAME" 2>&1 | grep -oE 'block_size[= ]+[0-9]+' | sort | uniq -c | tr -s ' ' | tr '
' ';')"
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
IMG=qwen38-27b-rtx3090:pr43-swpad
PIN="$(cygpath -w "$PWD/results/raw/v028/.pin_kernel.py")"
pin () { MSYS_NO_PATHCONV=1 docker run --rm -v qwen38-27b-rtx3090_qwen-cache:/cache -v "$PIN:/tmp/pin.py:ro" --entrypoint /app/venv/bin/python "$IMG" /tmp/pin.py "$@"; }
GOOD=9f8209ba4674079d3586dbf058fbe285f7bd7e211405b77506c5f1a52f248125; BAD=0b5880ea97ea2dcfd432644c85af755ff1ce468dfda0392a377b95f63b5f2ac5
# good tree, force the bad draw's choices, one kernel per cell (both-config args select this tree)
pin $GOOD chunk_scaled_dot_kkt_fwd_kernel '{"BK": 64}' 8 3;  mcell 1 pc_good_kkt v028pin-good-kkt-bad start_qwen.sh fast off -e VLLM_DISABLE_COMPILE_CACHE=0 -e "EXTRA_ARGS=--compilation-config {\"custom_ops\":[\"+rms_norm\",\"+silu_and_mul\"],\"max_cudagraph_capture_size\":32,\"inductor_compile_config\":{\"combo_kernels\":false,\"benchmark_combo_kernel\":false}}"; pin $GOOD restore
pin $GOOD merge_16x16_to_64x64_inverse_kernel '{}' 4 2;      mcell 1 pc_good_merge v028pin-good-merge-bad start_qwen.sh fast off -e VLLM_DISABLE_COMPILE_CACHE=0 -e "EXTRA_ARGS=--compilation-config {\"custom_ops\":[\"+rms_norm\",\"+silu_and_mul\"],\"max_cudagraph_capture_size\":32,\"inductor_compile_config\":{\"combo_kernels\":false,\"benchmark_combo_kernel\":false}}"; pin $GOOD restore
pin $GOOD recompute_w_u_fwd_kernel '{}' 8 4;                 mcell 1 pc_good_wu v028pin-good-wu-bad start_qwen.sh fast off -e VLLM_DISABLE_COMPILE_CACHE=0 -e "EXTRA_ARGS=--compilation-config {\"custom_ops\":[\"+rms_norm\",\"+silu_and_mul\"],\"max_cudagraph_capture_size\":32,\"inductor_compile_config\":{\"combo_kernels\":false,\"benchmark_combo_kernel\":false}}"; pin $GOOD restore
# bad tree, force the good draw's choices (cache-on args select this tree)
pin $BAD chunk_scaled_dot_kkt_fwd_kernel '{"BK": 32}' 4 4;   mcell 1 pc_bad_kkt v028pin-bad-kkt-good start_qwen.sh fast off -e VLLM_DISABLE_COMPILE_CACHE=0; pin $BAD restore
pin $BAD merge_16x16_to_64x64_inverse_kernel '{}' 2 2;       mcell 1 pc_bad_merge v028pin-bad-merge-good start_qwen.sh fast off -e VLLM_DISABLE_COMPILE_CACHE=0; pin $BAD restore
pin $BAD recompute_w_u_fwd_kernel '{}' 4 4;                  mcell 1 pc_bad_wu v028pin-bad-wu-good start_qwen.sh fast off -e VLLM_DISABLE_COMPILE_CACHE=0; pin $BAD restore
echo "PIN CYCLE DONE $(date -u +%H:%M:%SZ)"
