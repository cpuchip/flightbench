# Is the merge kernel's warp count an ACCURACY difference (a bug) or a rounding-order
# difference (math)?  Same inputs, autotune bypassed, compared against float64.
import sys, os, torch, itertools
sys.stdout.reconfigure(encoding='utf-8')
from vllm.triton_utils import triton
import importlib
m = importlib.import_module("vllm.third_party.flash_linear_attention.ops.solve_tril")
print("module:", m.__name__)
K = m.merge_16x16_to_64x64_inverse_kernel
solve_tril = m.solve_tril

def force(nw, ns):
    au = K.fn if hasattr(K, "fn") else K            # heuristics -> autotuner
    au.configs = [triton.Config({}, num_warps=nw, num_stages=ns)]
    for attr in ("cache", "configs_timings", "best_config"):
        c = getattr(au, attr, None)
        if isinstance(c, dict): c.clear()
        elif c is not None:
            try: setattr(au, attr, None)
            except Exception: pass

def reference(A):
    # (I + A)^-1 per 64x64 chunk, in float64 on the CPU
    B, T, H, BT = A.shape
    Ad = A.to(torch.float64)
    out = torch.zeros_like(Ad)
    for b in range(B):
        for h in range(H):
            for t0 in range(0, T, BT):
                blk = Ad[b, t0:t0+BT, h, :]
                if blk.shape[0] != BT: continue
                M = torch.eye(BT, dtype=torch.float64) + blk
                out[b, t0:t0+BT, h, :] = torch.linalg.inv(M)
    return out

torch.manual_seed(0)
dev = "cuda"
B, T, H, BT = 1, 1024, 8, 64
mask = torch.tril(torch.ones(BT, BT, device=dev), diagonal=-1)
print(f"{'scale':>6} {'warps':>6} {'max abs err':>13} {'mean abs err':>13} {'rel fro':>10}")
rows = {}
for scale in (0.05, 0.25, 1.0):
    A = (torch.randn(B, T, H, BT, device=dev) * scale)
    A = (A.reshape(B, T // BT, BT, H, BT) * mask[None, None, :, None, :]).reshape(B, T, H, BT)
    A = A.to(torch.bfloat16)
    ref = reference(A.cpu())
    outs = {}
    for nw in (2, 4):
        force(nw, 3)
        o = solve_tril(A.clone(), output_dtype=torch.float).cpu().to(torch.float64)
        outs[nw] = o
        err = (o - ref).abs()
        rel = torch.linalg.norm((o - ref).flatten()) / torch.linalg.norm(ref.flatten())
        print(f"{scale:6.2f} {nw:6d} {err.max().item():13.3e} {err.mean().item():13.3e} {rel.item():10.3e}")
    d = (outs[2] - outs[4]).abs()
    rows[scale] = (d.max().item(), d.mean().item(), (d > 0).float().mean().item())
    print(f"{'':6} {'2 vs 4':>6} {d.max().item():13.3e} {d.mean().item():13.3e}  disagreeing elements: {(d>0).float().mean().item()*100:.2f}%")
print("\nVERDICT INPUTS: if both warp counts sit at the same distance from the float64")
print("reference, the difference is rounding order, not accuracy.")
