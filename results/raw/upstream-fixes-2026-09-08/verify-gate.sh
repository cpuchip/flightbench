# CPU-only: apply the given patches to the fork's installed tree, then run the fork's own integrity gate.
SP=/app/venv/lib/python3.12/site-packages/vllm
for p in "$@"; do (cd $SP && patch -p1 -N -s < /fix/out/$p) && echo "applied $p" || { echo "APPLY FAILED $p"; exit 2; }; done
cd /app && echo "api-key-placeholder" > api_key.txt
bash verify.sh --no-server 2>&1 | grep -E "PASS|FAIL|WARN|verify:" | sed 's/^\s*//' | tail -40
