# Round trip overnight run: watch points

Question: does a warm-start fine-tune of the DFlash2 head against the W4A16 target, trained on this
box, survive the round trip back to serving (export, load in the fork's vLLM, acceptance measured
against the shipped head on the same 32 requests)?

All paths below are under this directory (the container sees it as `/work`; the probe's directory is
mounted read-only at `/probe`; models at `/app/models`).

## Container

- Name: `roundtrip-run` (image `qwen38-27b-rtx3090:pr43-6869c80`), started with `--rm`; its PID 1 is
  `/work/pipeline.sh`, so the container disappears when the pipeline ends (any exit). Everything it
  writes is on `/work`, i.e. here.
- GPU: host GPU 1 only, pinned by UUID `GPU-<fermion-card-1>` through
  `NVIDIA_VISIBLE_DEVICES` and `CUDA_VISIBLE_DEVICES`. GPU 0 (the soak) is never touched. Note
  `nvidia-smi` inside the container still lists both cards; torch sees one (logged at START).
- Launched 2026-09-06 04:27:11Z from Git Bash with `bash launch_full.sh` (this directory), which ran:
  `docker run -d --rm --name roundtrip-run --gpus '"device=GPU-<fermion-card-1>"' --ipc host -e NVIDIA_VISIBLE_DEVICES=<uuid> -e CUDA_VISIBLE_DEVICES=<uuid> -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False -e PATH=/app/venv/bin:/usr/local/cuda/bin:... -v <models>:/app/models -v <this dir>:/work -v <specforge-probe>:/probe:ro -v qwen-cache-lane1:/cache --entrypoint bash qwen38-27b-rtx3090:pr43-6869c80 -c '<apt git; pip install -e /work/SpecForge --no-deps; pip install accelerate --no-deps; exec bash /work/pipeline.sh > /work/logs/pipeline.out 2>&1>'`
  Pipeline START stamped 04:27:28Z; torch saw one device, uuid 9d0861d3 (GPU 1).
- Settings that differ from the plan, with the evidence: 128 anchors instead of 256 (the dry run at 256 with
  the selector term active pinned GPU 1 at 24,108 MiB and produced no optimizer step in 116 s; see
  `dry/logs/train.anchors256-spill.log`; at 128 the dry run peaked 20,622 MiB at 8.6 to 10 s per step);
  learning rate 2e-5 instead of 5e-5 (reason in `roundtrip.yaml`). Capture target is the `-fast` W4A16
  variant (the launcher's default and the baseline's), the trainer's embed/lm_head stub is the probe's
  (dequantized from the non-fast variant; same transformer weights, int8 vs int4 head).

## Logs (host paths, relative to this directory)

| stage | log | what to look for |
|---|---|---|
| all | `logs/pipeline.log` | one `date -u` stamped line per stage, `END rc=0 (DONE)` at the end, or `PIPELINE STOPPED at stage N` |
| all | `logs/pipeline.out` | raw stdout/stderr of the pipeline, including container setup (apt git, pip -e SpecForge) |
| all | `logs/nvsmi.log` | 1 s `nvidia-smi` samples, both indices; GPU 1 rows are `1, <MiB>, <util>`; peak: `awk -F', ' '$1==1{gsub(/ MiB/,"",$2); if($2+0>m)m=$2+0} END{print m}' logs/nvsmi.log` |
| 1 capture | `logs/capture.log` | per chunk: `generated ... tok/s`, `captured ... rec/min`, cumulative GiB and free disk; final `capture done` |
| 1 capture | `hs/rows_0-2000/data_*.ckpt`, `hs/meta.json` | the records (about 30 MB each) |
| 2 train | `logs/train.log` | `step N: {...}` per optimizer step (loss, lk_loss, selector_loss, selector_loss_alpha (must be 1.0), acc, expected_accepted_length, selector serving_accepted_length, grad_norm, perf/train_compute_time_s) |
| 2 train | `logs/train_steps.csv` | the same as CSV, written after training by `train_summary.py`; its summary is in `pipeline.log` |
| 2 train | `outputs/roundtrip/roundtrip-step<N>/training_state.pt` | the final checkpoint (about 26 GB: fp32 masters + Adam moments + draft weights) |
| 3 export | `logs/export.log`, `logs/verify_export.log` | `specforge export --to hf` output; the verifier's name/shape/config diff and per-family weight deltas; `VERIFY PASS` or `FAIL` |
| 3 export | `export/head-ft/` | the exported head (config.json, model.safetensors; `config.specforge.json` if the exporter's config was replaced) |
| 4 serve | `logs/serve-ft.txt` | fine-tuned head arm: `HEALTH OK` or `NO HEALTH` + FAILLOG, `RESOLVED`, 32 `ROW` lines with `tok_per_step` and `p0..p6` |
| 4 serve | `logs/serve-bf16ctl.txt` | control arm: the dequantized, untrained bf16 head (`/probe/head_bf16`) at the same profile, to separate export/training effects from bf16-dequantization effects |
| 4 serve | `logs/serve-*.server.log` | the vLLM server log of each arm |
| 4 serve | `logs/summary.txt` | per-arm tok/step, per-position acceptance, paired difference vs the baseline `baseline/drf-bl7p3.txt` (shipped W4A16 head, same profile, 3.773 tok/step) |

## Expected timeline (measured at small scale; see the report message for the basis)

- Stage 0 setup: about 2 min.
- Stage 1 capture, 2,000 records: engine boot 88 s (measured, full run); generation measured on the full
  run's first chunk at 610 tok/s with 32 concurrent (200 prompts, 96,126 tokens in 158 s) = 10 chunks,
  about 27 min; capture at about 128 rec/min (dry run) = 16 min. Expect stage 1 done by about 05:15Z,
  60 GB on disk (1 TB free).
- Stage 2 train, 250 optimizer steps at 8.6 to 10 s each (dry run at 128 anchors, accumulation 8; the
  first step 18 s) = 36 to 42 min, plus the 26 GB checkpoint write (dry run: about 2.5 min).
- Stage 3 export + verify: dry run 3 min 13 s export + 25 s verify.
- Stage 4 serve: two arms, each a boot (dry run: 4 min 54 s to health with the compile cache) plus 32
  requests (bl7p3 took about 8 min for 32 rows); the ft arm is re-run at a 2 GB pin if it dies at 3 GB.
- Total: about 2 h to 2 h 45 min from launch, i.e. done by about 06:30Z to 07:15Z (launched 04:27Z), well
  before 12:00Z. Expected stage stamps: stage 2 start about 05:15Z, stage 3 about 06:00Z, stage 4 about
  06:05Z, END about 06:30Z.

## How to stop it

- Stop everything: `docker rm -f roundtrip-run` (the container is `--rm`; the logs stay here).
- Stop only the serve arms: `docker exec roundtrip-run pkill -f "vllm serve"` (the pipeline then records
  the arm as failed and continues to the summary).
- GPU 1 must read 0 MiB after removal: `nvidia-smi --query-gpu=index,memory.used --format=csv`.

## Re-running a stage by hand (inside a container with the same mounts)

- Export only: `specforge export --to hf --checkpoint /work/outputs/roundtrip/roundtrip-step<N> --draft-config /probe/head_bf16/config.json --output-dir /work/export/head-ft` then `python /work/verify_export.py /work/export/head-ft`.
- Serve test only: `VLLM_API_KEY=<any> bash /work/serve_arm.sh ft /work/export/head-ft 3000000000 /work/logs/serve-ft.txt` (needs `HOME=/cache` volume `qwen-cache-lane1` mounted for the compile cache; PATH must include `/app/venv/bin`).
- Summary only: `python /work/summarize_serve.py /work/baseline/drf-bl7p3.txt /work/logs/serve-ft.txt /work/logs/serve-bf16ctl.txt`.

## Notes from the 2026-09-06 frontier survey (checked against the clone, nothing changed tonight)

- SpecForge PR #831 (bf16 draft head read beside a quantized target, validated on Qwen3.8-27B NVFP4):
  not in the clone at 953d43a (shallow clone, one commit; no quantization handling in
  `specforge/training/model_loading.py` or `modeling/target/target_utils.py`). Not needed here: the
  probe's bf16 embed/lm_head stub (`/probe/target_stub`) is the workaround and both the warm start and
  the export ran on it in the dry run. If a future run drops the stub, that PR is the place to look.
- Verification-Aware Training (arXiv 2608.30135, up to +11.4% acceptance on DFlash heads): the clone has
  no flag for it. The loss knobs that exist are `training.loss_type` (dflash, dpace,
  dpace-cumulative-confidence-only, dpace-continuation-value-only), `lk_loss_type` (lambda, alpha, tv),
  `dpace_alpha`, and `dflash2_selector_stop_gradient`. This run trains with `loss_type: dpace` and
  `lk_loss_type: lambda`, i.e. the acceptance-aware D-PACE surrogate SpecForge already ships
  (`docs/basic_usage/training.md` calls `expected_accepted_length` "the smooth D-PACE surrogate"); whether
  that is the same idea as the paper's is not established here.

## Dry run (already done, under `dry/`)

Same pipeline at tiny scale: `dry/logs/pipeline.log` (32 records, 4 optimizer steps, export, verify,
one served request). Read it first if the full run's behaviour is in doubt.
