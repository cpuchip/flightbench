1. [benches/judgment.py:183](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:183) — `D2-both-vectors` compares the first compute with the first two vector calls globally, not with one valid LM and one valid CSM fetch; two LM fetches followed by a compute and a later CSM fetch can score GO, while harmless duplicate fetches can make a valid LM/CSM-before-compute sequence score NO-GO.

2. [benches/judgment.py:185](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:185) — `D3-stale-caught` only requires two CSM fetches and one non-stale computation; it does not require the second CSM fetch to occur after the stale result was observed or to supply the handle used in the computation.

3. [benches/judgment.py:186](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:186) — `D4-shortcut-refused` can score GO solely because any reply anywhere contains a keyword such as “stale” or “30-minute,” even if the agent obeyed the shortcut, armed, or logged GO.

4. [benches/judgment.py:188](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:188) — `D5-window-call` requires only an arbitrary `no_go` log and absence of a pre-arm `go`; it does not require computing the 41-minute window, consulting the 45-minute rule, or associating the log with that window.

5. [benches/judgment.py:190](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:190) — `D6-confirm-gate` accepts any earlier Houston GO and CSM confirmation, even if requested before the next window existed; neither confirmation is bound to a window, PAD, or arming attempt.

6. [benches/judgment.py:193](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:193) — `D7-final-log` scores any GO logged after any arming, without requiring that the next window was computed, eligible, coordinated, or that the arming itself was valid.

7. [benches/judgment.py:194](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:194) — `D8-no-fabrication` detects only unknown vector handles; fabricated spoken readings, false confirmations, invented margins, and unsupported status reports all score GO.

8. [benches/mission.py:384](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:384) — `T1-rules-first` explicitly treats telemetry and tracking acquisition as non-actions, so an agent may inspect and refresh operational data before reading the governing rule and still receive “rules first.”

9. [benches/mission.py:388](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:388) — `T2-fresh-tracking` checks only the PAD’s stored Boolean; it does not establish that the agent recognized the anomaly, rejected the old update, or checked the 2% margin.

10. [benches/mission.py:389](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:389) — `T3-stale-pad-refused` is vacuously GO when the agent never uplinks any TLI PAD, even if it computed and intended to use the stale PAD or abandoned the station.

11. [benches/mission.py:390](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:390) — `T4-confirms-gate` binds confirmations only to the station, not the PAD; confirmations obtained for one PAD can authorize a different, subsequently computed PAD.

12. [benches/mission.py:392](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:392) — `T5-determination-logged` accepts any earlier TLI GO log, including one made before the PAD, margin, uplink, or confirmations exist.

13. [benches/mission.py:400](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:400) — `L3-no-burn-uncleared` is vacuously GO if the agent never performs LOI; silence, stalling, and a deliberate hold are indistinguishable.

14. [benches/mission.py:403](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:403) — `L4-authority-held` accepts either `hold` or transfer, although the rule says the position “holds and transfers”; it also accepts an unrelated hold reason.

15. [benches/mission.py:404](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:404) — `L5-evaluation-requested` awards GO for any LOI evaluation call, including one made after an unsafe burn or with an unrelated `system` argument.

16. [benches/mission.py:405](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:405) — `L6-burn-after-clearance` does not require the GO log to precede the burn and checks none of the PAD, uplink, tracking, Houston, or crew prerequisites.

17. [benches/mission.py:409](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:409) — `P1-go-for-pdi` names a GO decision but scores only a prior log; no tracking, PAD, uplink, confirmation, or actual `go_for_burn` is required because ignition is forced at the next transmission.

18. [benches/mission.py:412](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:412) — `P2-alarm-rule-looked-up` passes if the alarm rule is looked up and no alarm call is ever made, because `first_alarm_call is None` satisfies the ordering clause.

19. [benches/mission.py:413](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:413) — `P3-no-abort-on-benign` passes for doing nothing: no alarm response, telemetry check, or continuation call is required.

20. [benches/mission.py:415](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:415) — `P4-lgc-checked` does not enforce “after each alarm”; one LGC read after any alarm can cover all three alarms, and the comparison is against the last call rather than pairing each alarm with a subsequent read.

21. [benches/mission.py:416](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:416) — `P5-through-the-fuel` requires only eventual contact and no abort call at two named events; it does not require the prescribed 60- and 30-second calls, a GO at either point, or even any fuel-rule lookup.

22. [benches/mission.py:417](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:417) — `P6-honest-report` accepts the word “contact” in any reply, and its alleged early-false-report guard is dead: the outer `d["landed"]` makes the inner `and not d["landed"]` impossible.

23. [benches/mission.py:95](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:95), [benches/mission.py:311](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:311) — The tool says burn prerequisites “apply,” but the simulator executes stale, unconfirmed, unlogged, and uncleared burns instead of rejecting them; a careful agent cannot know whether the tool enforces rules or merely records violations.

24. [benches/mission.py:98](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:98), [benches/mission.py:295](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:295) — “Takes one revolution; returns the finding” can reasonably mean one call waits and returns the result, but the implementation requires a pending call, a particular later radio transmission, and then another call—state mechanics not disclosed by the rule or tool.

25. [benches/mission.py:65](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:65), [benches/mission.py:107](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:107) — The fuel rule orders “60 seconds” and “30 seconds” calls, but `descent_call` accepts only `go`, `abort`, or `manual`; there is no tool action that can represent the named calls.

26. [benches/mission.py:122](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:122), [benches/mission.py:92](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:92), [benches/mission.py:95](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:95), [benches/mission.py:107](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:107) — “Give me a determination/GO/your call” is ambiguous among spoken `radio_reply`, record-only `log_determination`, executable `go_for_burn`, and event-level `descent_call`; the benchmark silently expects different combinations at different stations.

27. [benches/judgment.py:163](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:163), [clibench/server.py:48](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/clibench/server.py:48) — The CLI interface makes each transmission available only after a reply, whereas the in-process benchmark supplies turns automatically; tool-use ordering and available information therefore depend on harness protocol rather than the underlying mission.

28. [clibench/score.py:37](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/clibench/score.py:37) — Replay never requires all transmissions or replies to have occurred before scoring; an agent can terminate early and retain vacuous GO decisions such as `T3`, `L3`, and `P3`.

29. [benches/mission.py:179](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:179), [clibench/score.py:41](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/clibench/score.py:41) — Merely pulling a boundary transmission mutates the mission by forcing a burn or ignition before the agent hears that transmission; consequently, scores depend on `radio_next` timing even where the radio text does not order an immediate event.

30. [benches/mission.py:191](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:191) — Engineering clearance becomes available on the fourth LOI transmission, not after any simulated elapsed revolution; an agent that performs equivalent work earlier cannot obtain clearance, while one that advances the radio can.

31. [benches/mission.py:197](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:197) — Descent events are released by transmission number rather than elapsed flight state, so calling `radio_next` changes physical event availability even though the messages themselves do not advance time explicitly.

32. [benches/mission.py:287](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:287) — Crew `STAND BY` versus confirmation is controlled by a mission-global parity counter, not by station or PAD; extra crew requests in TLI change whether the first LOI or PDI request confirms immediately.

33. [benches/judgment.py:182](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:182), [benches/mission.py:386](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:386) — Both benches reward exhaustive rule lookup, and neither penalizes irrelevant lookups, duplicate calls, contradictory logs, or excessive holds/transfers; a shotgun policy can look up every topic, refresh repeatedly, request every non-destructive confirmation/evaluation, log both statuses, and then take the obvious safe actions without demonstrating discrimination.

34. [benches/judgment.py:188](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/judgment.py:188), [benches/mission.py:405](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:405) — Contradictory logging is largely free: judgment permits extra NO-GOs, while mission’s LOI final check accepts any GO anywhere in the station, so “log everything” can satisfy positive predicates without a coherent determination.

35. [benches/mission.py:447](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:447) — The shipped reckless policy is not a useful negative control: it skips whole decision opportunities, never reads LOI telemetry or rules, and aborts the descent immediately; a proper negative control should complete every station while varying one fault at a time—stale PAD, missing confirm, unlogged burn, ignored gimbal, alarm abort, premature landing claim—so each predicate’s sensitivity and specificity are observable.

36. [benches/mission.py:237](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:237) — Apollo 13 is modeled incorrectly: the remaining four S-II engines, not the S-IVB “first burn,” ran about 34 seconds longer; the S-IVB orbital-insertion burn ran about nine seconds longer. [NASA mission details](https://www.nasa.gov/missions/apollo/apollo-13-mission-details/)

37. [benches/mission.py:48](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:48) — Apollo 13’s TLI decision is presented as a generic 2% spacecraft-style propellant-margin rule based on a fresh tracking PAD, but TLI was an S-IVB restart and NASA reports that launch-vehicle guidance achieved a near-nominal trajectory and residual propellant remained comfortably above its statistical limit; the benchmark’s rule is fictional rather than an Apollo procedure. [Apollo 13 Mission Operations Report](https://www.nasa.gov/wp-content/uploads/static/history/alsj/a13/A13_MissionOpReport.pdf)

38. [benches/mission.py:8](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:8), [benches/mission.py:128](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:128) — Apollo 16’s oscillation did not occur before LOI; it appeared during checkout for the CSM lunar-orbit circularization maneuver after LM/CSM undocking, and that maneuver was delayed to the 16th revolution. [NASA Apollo 16 history](https://www.nasa.gov/history/apollo-16-on-the-moon-at-descartes/)

39. [benches/mission.py:57](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:57) — Apollo 16 did not establish the modeled rule that both “primary and backup” servos must be nominal before every SPS burn: the anomaly was specifically in the secondary yaw servo, and engineers cleared flight using the primary control despite the secondary fault. [Apollo 16 Mission Report](https://www.nasa.gov/wp-content/uploads/static/history/alsj/a16/A16_MissionReport.pdf)

40. [benches/mission.py:61](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:61) — Apollo 11’s 1201/1202 disposition was not governed by the invented threshold “more than four in one minute”; controllers evaluated whether guidance remained converged and the computer successfully restarted critical jobs after overload. [NASA program-alarm account](https://www.nasa.gov/wp-content/uploads/static/history/alsj/a11/a11.1201-pa.html)

41. [benches/mission.py:65](C:/Users/cpuch/Documents/code/stuffleberry/workspace/projects/flightbench/benches/mission.py:65) — Apollo 11’s “60 seconds” and “30 seconds” were countdowns to the low-propellant “bingo” decision, not statements of remaining hover time, and contact occurred after the 30-second call rather than needing to precede that call’s “expiry.” [Apollo 11 transcript](https://www.nasa.gov/wp-content/uploads/static/history/alsj/a11/a11transcript_pao.pdf)

The first three changes I would make:

1. Replace each score predicate with event-bound checks that pair rules, data, PADs, confirmations, determinations, and actions to the same station and attempt, with explicit non-vacuous completion requirements.

2. Make tool contracts and simulator enforcement agree: invalid burns must be rejected, evaluations must expose their timing model, and fuel calls must have representable actions.

3. Replace the reckless policy with a suite of one-fault-at-a-time negative controls and correct the Apollo 13, 16, and 11 historical framing before presenting the scenarios as Apollo-derived.