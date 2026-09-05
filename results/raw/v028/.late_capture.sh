#!/bin/bash
# LATE LOG CAPTURE: the cell scripts save the engine log excerpt right after health, before the client
# runs. Anything printed lazily on the first real request (a Triton autotune race for kernels that only
# run under sampling, for example) is missed, and the containers are --rm. This watcher polls every
# running cell container of the queue and keeps the latest grep of its log in late-<name>.txt, so the
# final capture is within 30 s of the cell's end. Started 2026-09-05 after r7a's excerpt held no autotune
# lines at all (the warm AOT cache bakes the GDN winners for warm shapes; only new shapes re-race at boot).
PAT='autotun|best config|Warmed|rejection|draft_logits|Capturing|non-default args'
while true; do
  for c in $(docker ps --format '{{.Names}}' | grep -E '^(r7[a-d]|cgn7[ab]|q16_7|t11|sa0_7[abc]|pc0[cd]|p7[ab]|g7t[123])$'); do
    docker exec "$c" sh -c "grep -aiE '$PAT' /tmp/server.log | cut -c1-400" > "late-$c.tmp" 2>/dev/null && mv -f "late-$c.tmp" "late-$c.txt"
  done
  sleep 30
done
