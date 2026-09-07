import json, glob, os, sys
sys.stdout.reconfigure(encoding='utf-8')
base = "/cache/.cache/vllm/torch_compile_cache/torch_aot_compile"
out = {}
for f in glob.glob(f"{base}/**/*.autotune.json", recursive=True):
    name = os.path.basename(f)[:-len(".autotune.json")]
    try: d = json.load(open(f))
    except Exception: continue
    best, bt = None, None
    for cfg, times in d.get("configs_timings", []):
        t = min(times) if isinstance(times, list) and times else times
        if not isinstance(t, (int, float)): continue
        if bt is None or t < bt: bt, best = t, cfg
    if best is not None:
        out[name] = {"num_warps": best.get("num_warps"), "num_stages": best.get("num_stages"),
                     "kwargs": best.get("kwargs"), "t_ms": bt}
print(json.dumps(out, sort_keys=True))
