---
id: TASK-0068
title: String building with acc + x in a tail call is quadratic
status: pending             # pending | going-on | blocked | completed
created: 2026-11-10
completed:
requirements: [FR-COMP-011]
tests: [TS-COMP-011]
security: []
context_files: [docs/etc/compiler_optimizations.md, src/main/ridgun/lib/compiler.rg]
scope: [src/main/ridgun/lib/compiler.rg, tests/cases/perf/, docs/etc/compiler_optimizations.md]
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0068 — String building with acc + x in a tail call is quadratic

## Goal (one sentence)
`rep x n acc = rep x (n - 1) (acc + x)` appends in place and runs in linear time on both backends.

## Plan
- [ ] Find why `acc + x` copies `acc`: `lower tco arg expr` moves locals into `::` (`OpConcat`) but has no clause for string `+`; check whether the runtime `+` appends in place when the left string is unique.
- [ ] Move the left operand on its last use (and append in place in the runtime if it does not).
- [ ] Perf case (100 000 appends well under 1 s, with `max-ms`), OPT doc note.

## Progress log (append-only, newest last)
- 2026-11-10: Found while fixing TASK-0067: 100 000 rounds of `rep "a" n ""` take 2.3 s with 0.9.51 stage 1 (quadratic). The user asked to fix it after TASK-0066/0067.

## Files changed (keep current)
-
## Verification performed (command → result, newest last)
-
## Exact next actions
1. Start after TASK-0066 and TASK-0067 are committed.

## Decisions / open questions
## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
