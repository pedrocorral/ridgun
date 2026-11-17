---
id: TASK-0099
title: Per-phase timings of the compiler and scaling tests for each phase and for the runtime (find where a slowdown is, not search from scratch)
status: pending             # pending | going-on | blocked | completed
created: 2026-11-17
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0000 — Title

## Goal (one sentence)
## Plan
- [ ] step
## Progress log (append-only, newest last)
- 2026-11-17: Segment tests written (`tests/segments/run.sh`, `phase_probe.ridgun`, docs/etc/testing_in_segments.md). Measured: building the compiler with itself 171 s = front end 17 s + IR 20 s + `opt -O2` 106 s + `llc` 45 s + `ld`; `opt -O1` 78 s. The parser is quadratic in the statements of one function (500: 8 ms, 1 000: 24, 2 000: 111, 4 000: 483; lexer, type checker and analyzer are linear): `prepend stmt s (ss, rest) = ([s] :: ss, rest)` copies the list at each statement, because `borrow pat ok (PatTuple _)` makes the tuple a borrowed argument and the clone of `ss` makes the list shared. Fix for the parser: an accumulator instead of the tuple; general fix: do not borrow a parameter whose bound variable is extended in place, and release an owned tuple once its fields are bound. ADR-0015 proposes the main remedy (chunks of the call graph, memoized by content, parallel).
- YYYY-MM-DD: …
## Files changed (keep current)
-
## Verification performed (command → result, newest last)
-
## Exact next actions
1.
## Decisions / open questions
## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
