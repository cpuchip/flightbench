#!/bin/bash
# wait for the patched arm to serve, capture its boot lines, run two cohort arms (seeds 1-4, 5-8), pair against main-a1/a2.
set -u
U="$(cd "$(dirname "$0")" && pwd)"; MT="$U/../maintest"
NAME=${NAME:-qwen-fix-test}; PORT=${PORT:-18021}; TAG=${TAG:-fix}
log(){ echo "$(date -u +%H:%M:%SZ) $*"; }
for i in $(seq 1 150); do
  code=$(curl -s -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:$PORT/health); [ "$code" = 200 ] && break
  docker ps --format '{{.Names}}' | grep -q "^$NAME$" || { log "container $NAME died"; docker logs "$NAME" 2>&1 | tail -20; exit 2; }
  sleep 5
done
[ "$code" = 200 ] || { log "NO HEALTH after 12.5 min"; docker logs "$NAME" 2>&1 | tail -20; exit 3; }
log "HEALTHY $NAME"
docker exec "$NAME" bash -c 'grep -E "^GATE|^PATCH|GPU KV cache size|draft_sample_method|Graph capturing finished|lookup-augmented|speculative_config" /tmp/server.log | cut -c1-220' | sed 's/^/  boot: /'
NAME=$NAME PORT=$PORT bash "$MT/run-arm.sh" "$TAG-a1" 1,2,3,4 2>&1 | grep -E "^ARM|rows=" 
NAME=$NAME PORT=$PORT bash "$MT/run-arm.sh" "$TAG-a2" 5,6,7,8 2>&1 | grep -E "^ARM|rows="
log "=== paired: $TAG-a1 vs main-a1 ==="; python "$U/pair.py" "$MT/cohort-main-a1.txt" "$MT/cohort-$TAG-a1.txt"
log "=== paired: $TAG-a2 vs main-a2 ==="; python "$U/pair.py" "$MT/cohort-main-a2.txt" "$MT/cohort-$TAG-a2.txt"
log "=== pooled (both seed sets) ==="; cat "$MT/cohort-main-a1.txt" "$MT/cohort-main-a2.txt" > /tmp/pool-main.txt; cat "$MT/cohort-$TAG-a1.txt" "$MT/cohort-$TAG-a2.txt" > /tmp/pool-$TAG.txt; python "$U/pair.py" /tmp/pool-main.txt /tmp/pool-$TAG.txt
log "arms chain done"
