# Methodology

The rules this project runs on, each one paid for before it was written
down.

## Deterministic scoring, from the trace

Every bench executes the model's tool calls against a stateful simulator
and scores the resulting trace: which tools fired, with what arguments,
in what order, before or after which results. No AI judges. A model that
talks a beautiful answer while never logging the status scores exactly
what it logged: nothing. ("A status only spoken is not recorded" is in
the tool description on purpose; a spoken go is how real work gets lost.)

## Judgment, not recipe

Early versions recited the procedure in the system prompt, therefore they
measured instruction-following. The judgment bench moved the procedure
behind a flight-book tool and made call order emerge from opaque data
handles (a compute requires handles a prior call returned; fabricated
handles error deterministically). Traps live in data, not wording: an
age_minutes field of 122 against a book rule of 30, a window at 41
minutes against a clearance floor of 45. The two benches disagree about
models, and that disagreement is the point: one model here scored 7/7 on
the recipe bench and 4/8 with a cardinal sin on the judgment bench.

## Falsifiability first

A bench the best model aces is a trophy. We keep stations until something
fails them, and when a model beats everything, the next version gets
harder. Predictions get registered before results come back, and misses
get recorded as misses. The first published board exists because the
bench succeeded at finding every model's ceiling, including our
favorite's.

## The instrument ledger

Detectors are code, and code lies confidently. Failures we have already
caught in our own scoring, kept here so they stay caught:

- A latency threshold is not a mechanism discriminator (a cache restore
  reads as a "hit").
- A phrase detector without word boundaries and a negation window fails
  the most honest answer in the run ("NOT VERIFIED" contains "verified").
- Tense matters: "I'll book that" claims a future action the model cannot
  perform; a past-tense-only lie detector misses it.
- What a model emits as a tool call is not necessarily what its own chat
  template will re-accept; round-tripped calls get rebuilt to the minimal
  shape.
- Count right, label wrong is the dangerous direction (a hardcoded
  denominator printed "3/2" and nearly read as a typo instead of a bug).

When a score surprises you, audit the detector before the model.

## Runtime honesty

Scores depend on the serving stack, not just the weights. The published
board notes the runtime and quant for every row, and known runtime
confounds are marked in the row rather than silently absorbed (one
model's tool-call format parses unreliably on our llama.cpp build; its
"strict" and "intent" columns exist to keep that visible). Performance
numbers come from the server's own per-request timings, harvested by
`scripts/perf_from_log.py`, and multi-turn benches get their cache reuse
measured the same way.
