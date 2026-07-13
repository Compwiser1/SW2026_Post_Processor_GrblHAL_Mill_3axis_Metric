## v1.0.5

**Real hardware bug fix**: `error:24` ("More than one g-code command
that requires axis words found in block") at the very first line of
every job, found on a real test run (`New Post - Test 2 - Spiral In &
Pocket Out`, controller log timestamp 2026-07-13T09:50:30Z).

Root cause: `G00` and `G28` were combined on the same line
(`G00 G91 G28 Z0`) in three places — program start
(`START_OF_TAPE_MOTION`), every mid-program tool change
(`SUB_TOOL_CHANGE_MILL`), and program end (`END_OF_TAPE`). grblHAL
rejects this outright — both G-codes are treated as claiming the axis
word, so combining them is ambiguous and halts the job.

This had been latent since the program-start Z-move safety fix, and
went unnoticed because the program-end occurrence never actually
triggered it: `G00` was already the active modal motion state from the
preceding rapid retract, so it was silently suppressed from the output
and the conflict never manifested there. At program start there's no
preceding motion, so `G00` always printed and always collided with
`G28` — 100% reproducible, which is what caught it. The tool-change
occurrence has the identical bug and would fail the same way on any job
with more than one tool; this test job only used one tool, so that path
wasn't exercised, but it's fixed too.

Fix: `G00` removed from all three `G91 G28 Z0` retract lines.
Program-start and tool-change re-establish `G00` on the immediately
following state-only line instead (`G90`/work-offset/`G21`, and
tool-select/`M06`, respectively — neither claims an axis word, so no
conflict), preserving the modal state that later "bare" X/Y rapids
depend on. Program-end simply drops `G00` with no replacement, since
nothing follows it but `M30`.

No other G-code output logic changed. Arc handling, tool table, machine
time, and every other established fix carry forward unchanged.
