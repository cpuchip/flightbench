#!/bin/bash
# OFF REPLICATE AT WIDTH 15 (registered 2026-09-05 10:50Z after the second fresh-eyes review): sa0_15 (SPEC_ATTN=0, width 15) ran 23.6 ms
# against 56.5 but returned a one-token completion on prompt 5 seed 2, so "acceptance intact" was withdrawn. One more boot of the
# same configuration, every completion length printed (LENGTHS line). Readings registered: a second one-token row on the same
# prompt and seed makes the kernel-off path a suspect for the output; a clean boot at ~23.6 leaves the timing replicated and
# the one-token row a sampling event to be counted, not a defect; a slow boot (~56) says the first off timing was a single
# observation. Waits on the cold pair (PID 745150).
# WIDTH-7 TRIO WITH THE SPLIT-KV VERIFY ATTENTION OFF. sa0_15 read 23.6 ms/step (56.5 with the kernel
# on): the kernel at QMAX 16 is the whole width-15 cost on this card. The default-width bimodality
# (23 or 45 by boot with the kernel on at QMAX 8) is either the same kernel, or the GDN autotune race
# (the forced-first GDN configs cost 45-47 at width 7). Three boots at width 7 with SPEC_ATTN=0, winners
# printed. Registered: all three near 23 means the bimodality lives in the split-KV kernel or in what it
# shares with the race; a 23-or-45 split with the kernel off means the bimodality is the GDN race alone
# and the two findings are separate. Waits on the qmax cell and the fallback bracket.
#!/bin/bash
#!/bin/bash
LOCK=/tmp/sa015b.lock
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then echo "REFUSING: live run $(cat "$LOCK")"; exit 3; fi
echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
while kill -0 745150 2>/dev/null; do sleep 30; done  # wait for the cold pair (end of the card-0 queue)
MODELS='C:\Users\cpuch\Documents\code\stuffleberry\workspace\projects\qwen38-27b-rtx3090\models'
OUTD="results/raw/v028"; TK=kv-probe-key
CARD=GPU-206a1b8d-47c3-0dba-4ddb-e61c58306387; PORT=18020
VOL=qwen-cache-lane0; IMG=qwen38-27b-rtx3090:pr43-6869c80
SP="C:/Users/cpuch/AppData/Local/Temp/claude/C--Users-cpuch-Documents-code-stuffleberry-workspace/a6dde1ae-c949-48c9-90f4-e42fb81edeb5/scratchpad"
CLIENT_B64=$(base64 -w0 < "$SP/perpos_client.py")
FIELD='sed -i "s|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS}|\\\\\"num_speculative_tokens\\\\\":\$DRAFT_TOKENS,\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|" /app/single-user/start_qwen.sh; '
BLOCK='sed -i "s|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\"}|\\\\\"draft_sample_method\\\\\":\\\\\"probabilistic\\\\\",\\\\\"rejection_sample_method\\\\\":\\\\\"block\\\\\"}|" /app/single-user/start_qwen.sh; '
arm () {  # name tokens extra-docker-args
  NAME=$1; TOK=$2; EXTRA=${3:-}; PRE="$FIELD"
  docker rm -f "$NAME" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 docker run --rm --name "$NAME" --gpus "\"device=$CARD\"" --ipc host \
    -v "$VOL":/cache -v "$MODELS":/app/models \
    -e CUDA_VISIBLE_DEVICES=$CARD -e HOME=/cache -e VLLM_API_KEY=$TK -e PORT=$PORT -e ARM=$NAME \
    -e SPEC=dflash2 -e CTX=fast -e DFLASH_TOKENS=$TOK -e PREFIX_CACHE=1 -e TRITON_PRINT_AUTOTUNING=1 $EXTRA \
    -e INT8_ACT=int8 -e "INT8_LAYERS=mlp|linear_attn|self_attn" -e PREFILL_ATTN=int8 \
    -e GPU_UTIL=0.90 -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 -e VLLM_NO_USAGE_STATS=1 -e CLIENT_B64="$CLIENT_B64" \
    --entrypoint bash "$IMG" -c "$PRE"'
      cd /app && echo "$VLLM_API_KEY" > api_key.txt
      export PATH=/app/venv/bin:$PATH
      echo "SPEC_CFG_LINE $(grep -n "method.*dflash.*num_speculative_tokens" single-user/start_qwen.sh | head -1 | cut -c1-220)"
      nohup bash single-user/start_qwen.sh > /tmp/server.log 2>&1 &
      for i in $(seq 1 180); do sleep 5; curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health && break; done
      curl -sf -o /dev/null http://127.0.0.1:'"$PORT"'/health || { echo "NO HEALTH"; echo "FAILLOG_BEGIN"; grep -n -m1 -B3 -A40 -iE "Traceback|Error|error|assert" /tmp/server.log | cut -c1-300 | head -80; echo "FAILLOG_END"; tail -15 /tmp/server.log | cut -c1-300; exit 1; }
      echo "RESOLVED DFLASH_TOKENS=$DFLASH_TOKENS QMAX=${VLLM_SPEC_DECODE_ATTN_QMAX:-unset} SPEC_ATTN=${SPEC_ATTN:-unset} VLLM_SPEC_DECODE_ATTN=${VLLM_SPEC_DECODE_ATTN:-unset} FORCE_FIRST=${VLLM_TRITON_FORCE_FIRST_CONFIG:-unset} ASYNC_SCHED=${ASYNC_SCHED:-unset} $(grep -oE "async_scheduling[=: ]+(True|False)" /tmp/server.log | head -1) $(grep -oE "\-\-(no-)?async-scheduling" /tmp/server.log | head -1) $(grep -oE "num_speculative_tokens[^,]{0,10}" /tmp/server.log | head -1) $(grep -oE "draft_logits=(True|False)" /tmp/server.log | head -1) $(grep -oiE "rejection_sample_method[=: ]+[a-z]+|use_block_verification[=: ]+[A-Za-z]+" /tmp/server.log | head -2 | tr "\n" " ") $(grep -oE "drafting [0-9]+ tokens per step" /tmp/server.log | head -1)"
      echo "SERVERLOG_BEGIN"; grep -aiE "speculative_config|SpeculativeConfig|rejection_sample|num_speculative_tokens|async_scheduling|async-scheduling|enable_prefix_caching|Capturing CUDA graph|cudagraph|force.first|first valid config|draft_logits|max_num_seqs|max_model_len|autotun|best config" /tmp/server.log | head -400 | cut -c1-600; echo "SERVERLOG_END"
      echo "NONDEFAULT_LINE $(grep -m1 "non-default args" /tmp/server.log | cut -c1-3000)"
      echo "$CLIENT_B64" | base64 -d > /tmp/perpos_client.py
      ( while true; do echo "LINK $(date -u +%H:%M:%S) $(nvidia-smi --query-gpu=pcie.link.width.current,pcie.link.gen.current,clocks.sm,power.draw,utilization.gpu --format=csv,noheader)"; sleep 30; done ) &
      PORT='"$PORT"' VLLM_API_KEY="$VLLM_API_KEY" ARM="$ARM" python /tmp/perpos_client.py
    ' > "$OUTD/sa015b-$NAME.txt" 2>&1
  echo "LKCOST $NAME exit=$? $(grep -aE 'RESOLVED|NO HEALTH|SPEC_CFG_LINE' "$OUTD/sa015b-$NAME.txt" | head -2 | tr '\n' ' ' | cut -c1-300)"
  echo "LKCOST $NAME rows=$(grep -ac '^ROW ' "$OUTD/sa015b-$NAME.txt")"
}
# reduced to one boot 2026-09-05 16:30Z: the default-width bimodality is a single observation (std7), so the trio
# no longer buys a decision; one boot still answers whether SPEC_ATTN=0 costs anything at the default.
arm sa0_15b 15 "-e SPEC_ATTN=0"
echo "LENGTHS $(grep -a "^ROW " "$OUTD/sa015b-sa0_15b.txt" | grep -oE "prompt=[0-9]+ seed=[0-9]+|out=[0-9]+" | paste - - | awk "$3 != \"out=1024\"" | tr "
" ";")"
echo "LKCOST SA015B DONE $(date -u +%H:%M:%SZ)"
