PY=/app/venv/bin/python; $PY -m pip install -q pytest 2>&1 | tail -1
mkdir -p /tmp/t/tests/v1/spec_decode; cp /fix/tests/v1/spec_decode/test_rejection_sampler_utils_oldapi.py /tmp/t/tests/v1/spec_decode/test_oldapi.py; cd /tmp/t
echo "===== UNPATCHED tree, adapted test (draft on the shared stream, as the old API does): expect the unbiasedness assertion to FAIL"
$PY -m pytest -q --no-header -p no:cacheprovider --tb=line "tests/v1/spec_decode/test_oldapi.py::test_gumbel_drafted_rejection_sample_is_unbiased" 2>&1 | grep -vE "Warning|warn\(|^\s*$|^--" | tail -8
