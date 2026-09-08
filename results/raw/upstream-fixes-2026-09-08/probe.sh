PY=/app/venv/bin/python
$PY - <<'PYEOF'
import torch
print("device:", torch.cuda.get_device_name(0), "cc", torch.cuda.get_device_capability(0))
from vllm.v1.attention.backends.fa_utils import get_flash_attn_version
print("get_flash_attn_version():", get_flash_attn_version())
from vllm.v1.attention.backends.flash_attn import FlashAttentionMetadataBuilder
import inspect
src=inspect.getsource(FlashAttentionMetadataBuilder.__init__)
print("aot_schedule rule in builder:", [l.strip() for l in src.splitlines() if "aot_schedule" in l][:2])
PYEOF
