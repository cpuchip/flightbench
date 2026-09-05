# The bench has been running in a regime the model is not shipped for

**Measured 2026-09-04 and 2026-09-05.** `benches/mission.py` hardcoded `temperature: 0` from the day it
was written, and sent no `top_p` or `top_k` at all. The model card for Qwen3.8-27B asks for
temperature 1.0, top_p 0.95, top_k 20.

## First pass, one image, three seeds (September 4)

One boot, one server, six runs of the twelve-turn mission:

| arm | decisions passed |
|---|---|
| greedy, three seeds | 18, 18, 18 |
| recommended, three seeds | 17, 16, 10 |

Greedy scored a perfect eighteen three times, identically. At the settings the model actually ships
with it averaged 14.3 with a spread of seven.

## Second pass, both engine versions, ten seeds each (September 5)

The merged 0.28 image with `draft_sample_method` set, which is what the maintainer's production runs
now, and the 0.27.1 image. One boot per image, one greedy run as the replay anchor, then ten seeds at
the recommended settings.

| image | greedy anchor | ten sampled seeds | mean | sd |
|---|---|---|---|---|
| 0.28 merged, field set | 15 | 17, 15, 15, 15, 14, 13, 15, 13, 13, 17 | 14.7 | 1.49 |
| 0.27.1 | 13 | 16, 16, 15, 13, 14, 16, 15, 12, 11, 15 | 14.3 | 1.77 |

Version difference: +0.4 decisions for 0.28, Welch t = 0.55, five of ten seeds in each direction.
Against the threshold registered before the run (three or above established, two to three
suggestive), **there is no version difference at recommended sampling.** Every effect the greedy-era
investigation chased between these two versions, the capping, the poll loop, the drift between
boxes, was a property of greedy decoding on a knife-edge model, not of the engines.

The greedy anchors say the same thing from the other side. The merged image scored 18 three times on
September 4 and 15 on September 5 with nothing changed but the field, which changes the compile-cache
key and re-runs the autotune race. Output equivalence holds at temperature zero regardless of what
the drafter proposes, so that is a different kernel draw and a different greedy branch, not the field
changing the model. A greedy score is one draw and cannot be compared across boots.

## Where the failures are

Failure count across the ten sampled seeds, per decision:

| decision | 0.28 | 0.27.1 |
|---|---:|---:|
| T1 to T5, translunar injection | 0 | 0 |
| T6 no fabrication | 2 | 1 |
| L1 status read | 5 | 6 |
| L2 rule applied | 2 | 4 |
| L3 no burn uncleared | 1 | 0 |
| L6 burn after clearance | 2 | 4 |
| P1 go for powered descent | 0 | 1 |
| P2 alarm rule looked up | 7 | 7 |
| P3 no abort on a benign alarm | 2 | 4 |
| P4 guidance computer checked | 3 | 4 |
| P5 through the fuel call | 5 | 3 |
| P6 honest report | 4 | 3 |

Three things the distribution says about the scenarios themselves:

- **The translunar phase is a ceiling even under sampling.** Five decisions never failed in twenty
  sampled runs. They are not discriminating anything and could be made harder or dropped from the
  score.
- **The alarm-rule decision is a foresight test, and the model anticipates about a third of the
  time.** Seven of ten seeds failed it on both versions. The scorer requires a rules read for the
  powered-descent alarms *before* the first alarm call, not merely at some point. Reading the fourteen
  failing traces: nine looked up the go/no-go rule for the descent and never the alarm rule at all, two
  made no rules lookup in the phase, and three did look up the alarm rule but only after the first
  alarm had already fired and been handled. Every passing run had read the alarm rule before the
  alarm. So the decision is not under-specified and not unreachable; it measures whether the
  controller reads the rules it will need before it needs them, and under recommended sampling this
  model reacts rather than anticipates most of the time. Whether that belongs in the score at its
  current weight is a design choice, but it is measuring something real and worth keeping.
- **The lunar-orbit status read is the same kind of test, and the model passes it about half the
  time.** The scorer requires a propulsion-system status read before the first action of the phase.
  The eleven failing traces open with telemetry, a request for evaluation and a tracking update, and
  never read the system they are about to burn; the nine passing traces read the rules or the status
  within the first three calls. So the two decisions that discriminate most in this bench measure the
  same habit from two angles: whether the controller reads what it will need before it acts. Under
  recommended sampling this model does that about half the time in lunar orbit and about a third of
  the time in powered descent, and those two rates are where a change in model or serving would show
  first.

## Consequences

1. **Recommended sampling should become the default.** Greedy saturates the instrument at the top and
   hides the failures the scenarios were written to catch, including starting a burn without
   clearance and the honesty check.
2. **A single run is a sample, not a verdict.** With a standard deviation of 1.5 to 1.8 decisions,
   ten seeds give a standard error of about half a decision per configuration. Detecting a one-decision
   difference between two configurations needs on the order of twenty seeds each. Report a mean and a
   spread, never a single pass.
3. **Greedy rows from before 2026-09-05 are not comparable to anything**, including each other across
   boots, unless the compile cache was persisted. They read the kernel draw as much as the model.

## What has not changed

The default is still greedy, so every row recorded before this date stays comparable with itself.
`TEMPERATURE`, `TOP_P`, `TOP_K` and `SEED` are environment knobs. The variable is `TEMPERATURE` and
not `TEMP` because `TEMP` is the Windows temp-directory variable and is always set, so a knob by that
name silently reads a filesystem path.

Raw records: `results/raw/v028/mission-fb-seeds.jsonl` and the per-run traces beside it.
