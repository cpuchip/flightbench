"""Round trip, stage 3b: verify an exported head against the warm-start head and the shipped W4A16 head.

Usage: python verify_export.py <export_dir> [ref_bf16_dir=/probe/head_bf16] [shipped=/app/models/Qwen3.8-27B-DFlash2-W4A16]

Checks and logs every difference:
  1. tensor names + dtypes + shapes: export vs ref_bf16 (the dequantized shipped head, whose names SpecForge
     loaded 81/81 and whose names are the shipped names) and vs the shipped head with its quantized names
     mapped back (X.weight_packed / weight_scale / weight_shape -> X.weight).
  2. config.json: keys and values vs ref_bf16/config.json (dflash_config block, architectures, model_type...).
     If anything but transformers_version differs, the exporter's config is kept as config.specforge.json
     and ref_bf16's config.json (the shipped config minus quantization_config) is installed as config.json,
     because that is the config vLLM's qwen3_dflash2 loader is known to accept.
  3. weight deltas: per name family, mean |export - ref| and max |export - ref| in fp32, so the morning can see
     the trained weights (not the warm start) came through, and that nothing was zero-filled.
Exit 0 if names/shapes match exactly, 1 otherwise (the pipeline stops on 1).
"""
import os, sys, json, glob, struct, re, shutil
sys.stdout.reconfigure(encoding="utf-8")
import torch
from safetensors import safe_open


def header(path):
    out = {}
    for f in sorted(glob.glob(os.path.join(path, "*.safetensors"))):
        with open(f, "rb") as fh:
            n = struct.unpack("<Q", fh.read(8))[0]
            hdr = json.loads(fh.read(n))
        for k, v in hdr.items():
            if k == "__metadata__":
                continue
            out[k] = (v["dtype"], tuple(v["shape"]), f)
    return out


def fam(k):
    return re.sub(r"layers\.\d+\.", "layers.N.", k)


def main():
    exp = sys.argv[1]
    ref = sys.argv[2] if len(sys.argv) > 2 else "/probe/head_bf16"
    ship = sys.argv[3] if len(sys.argv) > 3 else "/app/models/Qwen3.8-27B-DFlash2-W4A16"
    ok = True
    print("export dir files:", sorted(os.listdir(exp)))
    e, r, s = header(exp), header(ref), header(ship)
    print(f"tensors: export {len(e)}, ref_bf16 {len(r)}, shipped {len(s)} (shipped counts packed triples)")
    # --- 1. names/shapes vs ref_bf16
    missing = sorted(set(r) - set(e)); extra = sorted(set(e) - set(r))
    if missing:
        ok = False; print(f"MISSING in export ({len(missing)}):"); [print("   ", k, r[k][:2]) for k in missing]
    if extra:
        ok = False; print(f"EXTRA in export ({len(extra)}):"); [print("   ", k, e[k][:2]) for k in extra]
    for k in sorted(set(r) & set(e)):
        if e[k][0] != r[k][0] or e[k][1] != r[k][1]:
            ok = False; print(f"SHAPE/DTYPE differs: {k}: export {e[k][:2]} vs ref {r[k][:2]}")
    # --- 1b. vs shipped names (dequantized mapping)
    ship_names = set()
    for k in s:
        m = re.match(r"(.*)\.weight_(packed|scale|shape)$", k)
        ship_names.add(m.group(1) + ".weight" if m else k)
    d1 = sorted(ship_names - set(e)); d2 = sorted(set(e) - ship_names)
    print(f"vs shipped (dequantized names): missing {len(d1)}, extra {len(d2)}")
    for k in d1: print("   missing:", k)
    for k in d2: print("   extra:", k)
    if d1 or d2: ok = False
    print("names/shapes vs ref_bf16:", "MATCH" if ok else "DIFFER")
    # --- 2. config
    ec_path = os.path.join(exp, "config.json"); rc_path = os.path.join(ref, "config.json")
    ec = json.load(open(ec_path)); rc = json.load(open(rc_path))
    diffs = []
    for k in sorted(set(ec) | set(rc)):
        if ec.get(k, "<absent>") != rc.get(k, "<absent>"):
            diffs.append((k, ec.get(k, "<absent>"), rc.get(k, "<absent>")))
    if diffs:
        print(f"config.json differences vs ref ({len(diffs)}):")
        for k, a, b in diffs:
            print(f"    {k}: export={json.dumps(a)[:200]}  ref={json.dumps(b)[:200]}")
    else:
        print("config.json: identical to ref")
    real = [d for d in diffs if d[0] != "transformers_version"]
    if real:
        shutil.copyfile(ec_path, os.path.join(exp, "config.specforge.json"))
        shutil.copyfile(rc_path, ec_path)
        print("config.json: exporter's saved as config.specforge.json; ref_bf16 config installed as config.json "
              f"({len(real)} substantive difference(s) listed above)")
    if "dflash_config" not in json.load(open(ec_path)):
        ok = False; print("FATAL: config.json has no dflash_config block")
    # --- 3. weight deltas vs ref (fp32), per family
    fams = {}
    nz_all = 0
    for k in sorted(set(r) & set(e)):
        with safe_open(e[k][2], framework="pt") as fe, safe_open(r[k][2], framework="pt") as fr:
            a = fe.get_tensor(k).float(); b = fr.get_tensor(k).float()
        d = (a - b).abs()
        f = fams.setdefault(fam(k), [0.0, 0.0, 0, 0.0])
        f[0] += d.sum().item(); f[1] = max(f[1], d.max().item()); f[2] += d.numel()
        f[3] = max(f[3], a.abs().max().item())
        nz_all += int((a != 0).any())
    print("weight deltas export - ref_bf16 (mean|d|, max|d|, max|export|) per family:")
    for k, (sm, mx, n, am) in fams.items():
        print(f"    {k:60s} mean {sm/max(n,1):.3e}  max {mx:.3e}  max|w| {am:.3e}")
    tot_mean = sum(v[0] for v in fams.values()) / max(sum(v[2] for v in fams.values()), 1)
    print(f"overall mean |delta| {tot_mean:.3e}; tensors with any non-zero value: {nz_all}/{len(set(r) & set(e))}")
    if nz_all < len(set(r) & set(e)):
        ok = False; print("FATAL: some exported tensors are entirely zero")
    print("VERIFY", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
