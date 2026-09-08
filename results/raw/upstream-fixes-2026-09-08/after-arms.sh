#!/bin/bash
# After the salt arms: all-three boot + arms (paired vs the salt arms), full gumbel test list on the
# patched tree, a Docker build of the salt branch as the maintainer would build it and a boot of that
# image to health, then card 1 restored (yield off) and the dead-man disarmed.
set -u
U="$(cd "$(dirname "$0")" && pwd)"; S="$U/.."; MT="$U/../maintest"; UW="$(cygpath -w "$U")"
FORK=<workspace>/projects/qwen38-pr43
CARD=GPU-<fermion-card-1>
log(){ echo "$(date -u +%H:%M:%SZ) $*"; }
rearm(){ W="$(cygpath -w "$S")"; T=$(powershell -NoProfile -Command "(Get-Date).AddMinutes($1).ToString('HH:mm')"); cmd //c "schtasks /create /f /sc once /st $T /tn deadman-card1-yield /tr \"\\\"$W\prod\restore-card1.cmd\\\"\"" >/dev/null 2>&1 && log "dead-man re-armed for local $T"; }
waithealth(){ # name port
  for i in $(seq 1 150); do c=$(curl -s -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:$2/health); [ "$c" = 200 ] && return 0
    docker ps --format '{{.Names}}' | grep -q "^$1$" || { log "$1 died"; docker logs "$1" 2>&1 | tail -15; return 2; }; sleep 5; done; log "$1 no health"; return 3; }
for i in $(seq 1 400); do grep -q "arms chain done\|died\|NO HEALTH" "$U/arms-fix.log" 2>/dev/null && break; sleep 5; done
grep -q "arms chain done" "$U/arms-fix.log" || { log "salt arms did not finish cleanly; stopping here"; exit 2; }
rearm 75
log "salt arm gate/patch lines:"; docker logs qwen-fix-test 2>&1 | grep -E "^GATE|^PATCH" | cut -c1-160
log "=== ALL THREE: boot ==="; docker rm -f qwen-fix-test >/dev/null 2>&1
PATCHES="draft-gumbel-salt.patch dflash-fa-aot-schedule.patch dflash-draft-rope-layout.patch" NAME=qwen-all3-test bash "$U/launch-fix-arm.sh"
TAG=all3 NAME=qwen-all3-test PORT=18021 bash "$U/arms-chain.sh" > "$U/arms-all3.log" 2>&1; log "all3 arms exit $?"; grep -E "HEALTHY|boot:|^ARM|rows=" "$U/arms-all3.log" | cut -c1-200
log "=== paired: all3-a1 vs fix-a1 (expect no difference) ==="; python "$U/pair.py" "$MT/cohort-fix-a1.txt" "$MT/cohort-all3-a1.txt"
log "=== paired: all3-a2 vs fix-a2 ==="; python "$U/pair.py" "$MT/cohort-fix-a2.txt" "$MT/cohort-all3-a2.txt"
log "all3 arm gate/patch lines:"; docker logs qwen-all3-test 2>&1 | grep -E "^GATE|^PATCH" | cut -c1-160
docker rm -f qwen-all3-test >/dev/null 2>&1
rearm 60
log "=== full gumbel test list on the salt-patched tree (no -x) ==="
MSYS_NO_PATHCONV=1 docker run --rm --gpus "device=$CARD" -e NVIDIA_VISIBLE_DEVICES=$CARD -e CUDA_VISIBLE_DEVICES=0 -e XFLAG=" " -e TAILN=14 --ipc host --shm-size 64m -v "$UW":/fix --entrypoint bash qwen38-27b-rtx3090:main-7ca84fc -c 'bash /fix/run-salt-tests.sh patched' 2>&1 | grep -E "passed|failed|FAILED|PASSED|=====" | cut -c1-200
log "=== build the salt branch as the maintainer would ==="
rm -rf "$S/build-salt"; git -C "$FORK" worktree prune; git -C "$FORK" worktree add -q "$S/build-salt" backport/pr54282-draft-gumbel-salt || { log "worktree failed"; }
( cd "$S/build-salt" && MSYS_NO_PATHCONV=1 docker build -t qwen38-27b-rtx3090:pr54282-salt . > "$U/build-salt.log" 2>&1 ); log "build exit $? ($(grep -c "" "$U/build-salt.log") log lines)"; grep -E "== patches/vllm-pr54282|verify:|FAIL|error|Error|Successfully|writing image" "$U/build-salt.log" | tail -8 | cut -c1-200
if docker image inspect qwen38-27b-rtx3090:pr54282-salt >/dev/null 2>&1; then
  rearm 45
  log "=== boot the BUILT image to health ==="; IMG=qwen38-27b-rtx3090:pr54282-salt NAME=qwen-built-test PATCHES=" " bash "$U/launch-fix-arm.sh"
  waithealth qwen-built-test 18021 && { log "HEALTHY built image"; docker logs qwen-built-test 2>&1 | grep -E "^GATE|GPU KV cache size|Graph capturing finished" | cut -c1-200; }
  docker rm -f qwen-built-test >/dev/null 2>&1
fi
log "=== restore card 1 ==="; curl -s -X POST -H 'Content-Type: application/json' -d '{"gpu":1,"on":false}' http://127.0.0.1:8090/api/yield; echo
cmd //c "schtasks /delete /f /tn deadman-card1-yield" >/dev/null 2>&1 && log "dead-man disarmed"
for i in $(seq 1 60); do st=$(curl -s -m 3 http://127.0.0.1:8090/api/status | python -c "import sys,json; d=json.load(sys.stdin); print([s['state'] for s in d['slots'] if s['name'].startswith('qwen3.6')][0])" 2>/dev/null); [ "$st" = healthy ] && break; sleep 5; done
log "35B slot state: ${st:-unknown}; card 1 used $(nvidia-smi --id=1 --query-gpu=memory.used --format=csv,noheader)"
log "after-arms chain done"
