FROM qwen38-27b-rtx3090:stock028-embed
COPY patches /tmp/patches
RUN SP=$(python3 -c "import importlib.util as u; print(u.find_spec('vllm').submodule_search_locations[0])") && for p in /tmp/patches/*.patch; do echo "== $p"; patch -p1 -N -d "$SP" < "$p" || exit 1; done
