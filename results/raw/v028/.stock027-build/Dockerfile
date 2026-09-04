FROM vllm/vllm-openai:v0.27.1
# stock 0.27.1 plus the one fork patch the checkpoint needs to load (AutoRound packs the embedding weights); nothing else.
COPY qwen3_5-embed-quant.patch /tmp/
RUN SP=$(python3 -c "import importlib.util as u; print(u.find_spec('vllm').submodule_search_locations[0])") && echo "site-packages: $SP" && patch -p1 -d "$SP" < /tmp/qwen3_5-embed-quant.patch
