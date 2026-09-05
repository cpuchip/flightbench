#!/bin/bash
# Gotchas 55 replication on this box: same six seeds, two orders, one boot. Prediction registered:
# drafts and accepted identical per seed across orders; drafted tokens may differ; tok/step identical.
set -u
LOCK=/tmp/order_arm.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-9d0861d3-75b2-b317-87c0-695bba368f1b; PORT=18021
VOL=qwen-cache-lane1; IMG=qwen38-27b-rtx3090:pr43-6869c80
NAME=order-arm
docker rm -f "$NAME" >/dev/null 2>&1
MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
  -v "$VOL":/cache -v "$MODELS":/app/models \
  -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT \
  -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=15 -e PREFIX_CACHE=1 \
  -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
  -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="IiIiR290Y2hhcyBlbnRyeSA1NSByZXBsaWNhdGlvbjogZG9lcyByZXF1ZXN0IE9SREVSIGNoYW5nZSBkcmFmdGVkIHRva2VucyB3aGlsZSBkcmFmdHMgYW5kCmFjY2VwdGVkIHN0YXkgZml4ZWQ/ICBPbmUgYm9vdCwgb25lIGNvbmZpZywgdGhlIHNhbWUgc2l4IHNlZWRzIHJ1biBpbiB0d28gb3JkZXJzLgpUaGUgY2xhaW0gcHJlZGljdHM6IGRyYWZ0cyBhbmQgYWNjZXB0ZWQgaWRlbnRpY2FsIHBlciBzZWVkIGFjcm9zcyBvcmRlcnM7IGRyYWZ0ZWQgdG9rZW5zCihhbmQgdGhlcmVmb3JlIGFjYy9kcmFmdGVkIGFuZCByb3VuZCBzaXplKSBtYXkgZGlmZmVyOyB0b2svc3RlcCBpZGVudGljYWwuIiIiCmltcG9ydCBqc29uLCBvcywgcmUsIHN5cywgdXJsbGliLnJlcXVlc3QKc3lzLnN0ZG91dC5yZWNvbmZpZ3VyZShlbmNvZGluZz0idXRmLTgiKQpQT1JUID0gb3MuZW52aXJvblsiUE9SVCJdOyBLRVkgPSBvcy5lbnZpcm9uWyJWTExNX0FQSV9LRVkiXQpCQVNFID0gZiJodHRwOi8vMTI3LjAuMC4xOntQT1JUfSIKTkFNRVMgPSAoImRyYWZ0cyIsICJkcmFmdF90b2tlbnMiLCAiYWNjZXB0ZWRfdG9rZW5zIikKCiMgVGhlIFJFQURNRS1wbHVzLWluc3RydWN0aW9uIHByb21wdCBzaGFwZSB0aGF0IHByb2R1Y2VkIGxvbmctYmxvY2sgZW50cmllcyBvbiB0aGUgb3RoZXIgYm94OwojIGEgcHJvbXB0IHRoYXQgbmV2ZXIgZW50ZXJzIHRoZSBsb25nIGJsb2NrIGNhbm5vdCBzaG93IHRoZSBlZmZlY3QgKGFsbCByb3VuZCA9PSA3LjAwMCkuCnJlYWRtZSA9IG9wZW4oIi9hcHAvUkVBRE1FLm1kIiwgZW5jb2Rpbmc9InV0Zi04IiwgZXJyb3JzPSJyZXBsYWNlIikucmVhZCgpWzo2MDAwXQpwcm9tcHQgPSByZWFkbWUgKyAiXG5cblN1bW1hcmlzZSB0aGUgYWJvdmUgaW4gZGV0YWlsLiIKCmRlZiBjb3VudGVycygpOgogICAgcnEgPSB1cmxsaWIucmVxdWVzdC5SZXF1ZXN0KEJBU0UgKyAiL21ldHJpY3MiLCBoZWFkZXJzPXsiQXV0aG9yaXphdGlvbiI6ICJCZWFyZXIgIiArIEtFWX0pCiAgICB0eHQgPSB1cmxsaWIucmVxdWVzdC51cmxvcGVuKHJxLCB0aW1lb3V0PTYwKS5yZWFkKCkuZGVjb2RlKCkKICAgIHJldHVybiB7bjogZmxvYXQocmUuc2VhcmNoKHJmIl52bGxtOnNwZWNfZGVjb2RlX251bV97bn1fdG90YWxce3tbXn19XSpcfX1ccysoWzAtOS5dKykiLCB0eHQsIHJlLk0pLmdyb3VwKDEpKQogICAgICAgICAgICBmb3IgbiBpbiBOQU1FU30KCmRlZiBydW4oc2VlZCk6CiAgICBiID0gY291bnRlcnMoKQogICAgYm9keSA9IGpzb24uZHVtcHMoeyJtb2RlbCI6ICJxd2VuMy44LTI3YiIsICJwcm9tcHQiOiBwcm9tcHQsICJtYXhfdG9rZW5zIjogMjU2LCAic2VlZCI6IHNlZWR9KS5lbmNvZGUoKQogICAgcnEgPSB1cmxsaWIucmVxdWVzdC5SZXF1ZXN0KEJBU0UgKyAiL3YxL2NvbXBsZXRpb25zIiwgZGF0YT1ib2R5LAogICAgICAgIGhlYWRlcnM9eyJDb250ZW50LVR5cGUiOiAiYXBwbGljYXRpb24vanNvbiIsICJBdXRob3JpemF0aW9uIjogIkJlYXJlciAiICsgS0VZfSkKICAgIGQgPSBqc29uLmxvYWQodXJsbGliLnJlcXVlc3QudXJsb3BlbihycSwgdGltZW91dD05MDApKQogICAgYSA9IGNvdW50ZXJzKCkKICAgIGRyID0gYVsiZHJhZnRzIl0gLSBiWyJkcmFmdHMiXTsgZHQgPSBhWyJkcmFmdF90b2tlbnMiXSAtIGJbImRyYWZ0X3Rva2VucyJdOyBhYyA9IGFbImFjY2VwdGVkX3Rva2VucyJdIC0gYlsiYWNjZXB0ZWRfdG9rZW5zIl0KICAgIHJldHVybiBkciwgZHQsIGFjLCBkWyJ1c2FnZSJdWyJjb21wbGV0aW9uX3Rva2VucyJdCgpvcmRlcnMgPSB7IkEiOiBbMSwgMiwgMywgNCwgNSwgNl0sICJCIjogWzYsIDUsIDQsIDMsIDIsIDFdfQpyZXMgPSB7fQpmb3IgbmFtZSwgc2VxIGluIG9yZGVycy5pdGVtcygpOgogICAgZm9yIHMgaW4gc2VxOgogICAgICAgIGRyLCBkdCwgYWMsIG91dCA9IHJ1bihzKQogICAgICAgIHJlc1sobmFtZSwgcyldID0gKGRyLCBkdCwgYWMpCiAgICAgICAgcHJpbnQoZiJPUkRFUlJPVyBvcmRlcj17bmFtZX0gc2VlZD17c30gZHJhZnRzPXtkcjouMGZ9IGR0b2s9e2R0Oi4wZn0gYWNjPXthYzouMGZ9ICIKICAgICAgICAgICAgICBmInJvdW5kPXtkdC9kciBpZiBkciBlbHNlIDA6LjNmfSB0b2tfcGVyX3N0ZXA9ezErYWMvZHIgaWYgZHIgZWxzZSAwOi4zZn0gb3V0PXtvdXR9IiwgZmx1c2g9VHJ1ZSkKCnByaW50KCJPUkRFUlNVTU1BUlkgc2VlZCB8IGRyYWZ0cyBBL0IgfCBkdG9rIEEvQiB8IGFjYyBBL0IgfCB2ZXJkaWN0IikKc2FtZV9kYSA9IHNhbWVfZHQgPSAwCmZvciBzIGluIG9yZGVyc1siQSJdOgogICAgYSwgYiA9IHJlc1soIkEiLCBzKV0sIHJlc1soIkIiLCBzKV0KICAgIHYgPSBbXQogICAgdi5hcHBlbmQoImRyYWZ0cz0iIGlmIGFbMF0gPT0gYlswXSBlbHNlICJkcmFmdHMhPSIpCiAgICB2LmFwcGVuZCgiYWNjPSIgaWYgYVsyXSA9PSBiWzJdIGVsc2UgImFjYyE9IikKICAgIHYuYXBwZW5kKCJkdG9rPSIgaWYgYVsxXSA9PSBiWzFdIGVsc2UgImR0b2shPSIpCiAgICBpZiBhWzBdID09IGJbMF0gYW5kIGFbMl0gPT0gYlsyXTogc2FtZV9kYSArPSAxCiAgICBpZiBhWzFdID09IGJbMV06IHNhbWVfZHQgKz0gMQogICAgcHJpbnQoZiJPUkRFUlNVTU1BUlkge3N9IHwge2FbMF06LjBmfS97YlswXTouMGZ9IHwge2FbMV06LjBmfS97YlsxXTouMGZ9IHwge2FbMl06LjBmfS97YlsyXTouMGZ9IHwgeycgJy5qb2luKHYpfSIsIGZsdXNoPVRydWUpCnByaW50KGYiT1JERVJWRVJESUNUIGRyYWZ0cythY2NlcHRlZCBpbnZhcmlhbnQgb24ge3NhbWVfZGF9LzYgc2VlZHM7IGRyYWZ0ZWQgdG9rZW5zIGludmFyaWFudCBvbiB7c2FtZV9kdH0vNiBzZWVkcyIsIGZsdXNoPVRydWUpCg==" \
  --entrypoint bash "$IMG" -c '
    cd /app && echo "$VLLM_API_KEY" > api_key.txt
    export PATH=/app/venv/bin:$PATH
    nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
    for i in $(seq 1 150); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
    curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; tail -15 /tmp/server.log; exit 1; }
    grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1
    echo "$CLIENT_B64" | base64 -d > /tmp/order_client.py
    PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" python /tmp/order_client.py
  ' > "$OUTD/order-arm.txt" 2>&1
echo "ORDER exit=$?"
grep -aE "draft_logits|ORDERROW|ORDERSUMMARY|ORDERVERDICT|NO HEALTH|Traceback|Error" "$OUTD/order-arm.txt" | sed "s/^/ORDER /"
echo "ORDER ARM DONE $(date -u +%H:%M:%SZ)"
