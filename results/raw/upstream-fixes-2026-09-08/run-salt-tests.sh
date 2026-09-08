#!/bin/bash
# Upstream's own tests for fe755c889 (the draft-noise salt), run inside the fork's image on a GPU:
# once UNPATCHED (the new assertions must FAIL: red), once with draft-gumbel-salt.patch applied
# (green). pytest is installed into the container's venv for the run (throwaway container).
# usage inside the container: bash /fix/run-salt-tests.sh {unpatched|patched}
set -u
MODE=${1:-unpatched}
SP=/app/venv/lib/python3.12/site-packages
PY=/app/venv/bin/python
$PY -m pip install -q pytest 2>&1 | tail -1
if [ "$MODE" = patched ]; then
  (cd $SP/vllm && patch -p1 -N < /fix/out/draft-gumbel-salt.patch >/dev/null) && echo "salt patch applied" || { echo "PATCH FAILED"; exit 2; }
fi
mkdir -p /tmp/t/tests/v1/worker /tmp/t/tests/v1/spec_decode
cp /fix/tests/v1/worker/test_gpu_gumbel_sample.py /tmp/t/tests/v1/worker/
cp /fix/tests/v1/spec_decode/test_rejection_sampler_utils.py /tmp/t/tests/v1/spec_decode/
cd /tmp/t
echo "===== $MODE: test_gpu_gumbel_sample.py"
$PY -m pytest -q ${XFLAG:--x} --no-header -p no:cacheprovider tests/v1/worker/test_gpu_gumbel_sample.py 2>&1 | tail -${TAILN:-8}
echo "===== $MODE: test_rejection_sampler_utils.py"
$PY -m pytest -q --no-header -p no:cacheprovider tests/v1/spec_decode/test_rejection_sampler_utils.py 2>&1 | tail -8
