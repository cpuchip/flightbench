# Scenario quarry: NASA SP-4205, Chariots for Apollo

The benches ground themselves in NASA SP-4205 (Chariots for Apollo, the
NASA history of the Apollo spacecraft program: public domain, and full of
real engineering judgment calls with real numbers attached). This file is
the quarry: passages harvested from the text that would make good future
scenarios, each with the verbatim line that anchors it. Mine it when
adding a bench.

## 1. The pogo limits call (limits-exceedance judgment)

The book, on the Saturn V's second unmanned flight: low-frequency
oscillations "caused the vehicle to bounce like a giant pogo stick for
about 30 seconds. Low-frequency modulations (known as the pogo effect) as
high as +/-0.6 g were recorded in the command module, which exceeded
design criteria (0.25 g was the upper limit permitted for manned flight
in Gemini)."

Scenario shape: feed telemetry showing 0.6 g against a 0.25 g manned
limit and ask for the crew-rating call. Numbers are in the document;
the model must find the limit, compare, and refuse to rate the vehicle
for crew. Variants: a reading of 0.24 g (inside the limit... does it
over-refuse?), and a reading in different units.

## 2. The helium-sphere hold (T-minus-3 recycle decision)

February 1966, AS-201: "Three seconds before ignition - at 9:00 the next
morning - a computer signaled that pressure in two helium spheres on the
S-IVB stage was low."

Scenario shape: a hold at T-3 seconds with an automated cutoff, then a
recycle-or-scrub decision tree: what must be verified before a recycle,
who has the authority, what the turnaround costs. Tests sequencing under
time pressure plus authority routing.

## 3. Deleting the rendezvous radar (redundancy trade study)

A real proposal: planners "began to think about omitting the rendezvous
radar from both the command and lunar modules," on the argument the units
were "doubly redundant, since rendezvous could be performed by the
command module pilot with the aid of data relayed by the Manned Space
Flight Network."

Scenario shape: the model must argue both sides of removing a redundant
system from a crewed vehicle, then make a recommendation with the
failure cases named. Tests whether it can hold "redundant" and
"safety-critical" in tension instead of pattern-matching to either.

## 4. The mass brackets (grounded arithmetic)

The mode-decision chapters carry competing lander mass estimates:
"Houston calculated that the target weight of the lunar landing module
would be 9,000 kilograms, but Chance Vought came up with a more
realistic figure of 13,600 kilograms."

Scenario shape: give calculation tools and the document; the model must
extract the right figures, not invent tighter ones, and carry the
uncertainty band through a fuel-budget computation. (This quote already
anchors the lander game grounding test that preceded these benches.)

## 5. Fuel-cell program management (subsystem triage)

"The fuel cell program was laden with technical and managerial
problems." The surrounding chapters track a subsystem that repeatedly
slipped while the vehicle around it moved on... and the eventual
battery-versus-fuel-cell decision.

Scenario shape: a standup-report scenario: given status snippets for
several subsystems, produce the triage: what blocks the critical path,
what escalates, what merely gets watched. Tests prioritization rather
than tool mechanics.

## 6. The mode decision itself (the big one, someday)

The book's spine is the lunar-orbit-rendezvous versus direct-ascent
versus earth-orbit-rendezvous decision: years of committees, changed
minds, and one famous advocate. A long-context bench could hand the
model large excerpts and require a decision brief with each faction's
strongest argument cited verbatim. Tests deep-context faithfulness at
the scale the document actually offers (the full text is ~1.2M
characters, roughly 300k tokens).

## Harvest rules

Every scenario built from this quarry keeps the anchor quote verbatim in
its docs, checked against the text before commit. If a number is not in
the book, the scenario says so instead of borrowing one. The book is the
ground truth the models get graded against; it has to stay ground truth
for us too.
