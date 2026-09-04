# usage: pin_kernel.py <tree-hash> <kernel> <kwargs-json> <num_warps> <num_stages> | pin_kernel.py <tree-hash> restore
import json, glob, os, sys, shutil
base = "/cache/.cache/vllm/torch_compile_cache/torch_aot_compile"
h = sys.argv[1]
files = glob.glob(f"{base}/{h}/**/*.autotune.json", recursive=True)
if sys.argv[2] == "restore":
    n = 0
    for f in files:
        if os.path.exists(f + ".orig"): shutil.copy(f + ".orig", f); os.remove(f + ".orig"); n += 1
    print("restored", n); sys.exit(0)
kernel, kw, nw, ns = sys.argv[2], json.loads(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
f = next(x for x in files if os.path.basename(x) == kernel + ".autotune.json")
if not os.path.exists(f + ".orig"): shutil.copy(f, f + ".orig")
d = json.load(open(f)); hit = 0
for cfg, times in d["configs_timings"]:
    if cfg.get("kwargs") == kw and cfg.get("num_warps") == nw and cfg.get("num_stages") == ns:
        d["configs_timings"][d["configs_timings"].index([cfg, times])][1] = [1e-6] * (len(times) if isinstance(times, list) else 1); hit += 1
json.dump(d, open(f, "w"))
print("pinned", kernel, kw, nw, ns, "matches", hit)
