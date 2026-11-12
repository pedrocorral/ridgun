---
id: TASK-0058
title: Refactor compiler code with chains of temporary variables into -> pipelines
status: pending             # pending | going-on | blocked | completed
created: 2026-11-07
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files:
  - src/main/ridgun/lib/compiler.ridgun
  - src/main/ridgun/lib/typecheck.ridgun
  - src/main/ridgun/lib/parser.ridgun
scope:
  - src/main/ridgun/lib/*.ridgun
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0058 — Refactor compiler code with chains of temporary variables into -> pipelines

## Goal (one sentence)
Review the compiler sources for chains of temporary variables (`st1 = ...`, `st2 = f st1`, `m1`, `m2` ...) and rewrite the ones that read better as `->` pipelines (`x -> f -> g`) or operators, without changing behaviour.

## Plan
- [ ] List the candidates: functions where each variable is used once, by the next line (typical in `compiler.ridgun`: `st0`/`st1`/`st2` code-emission chains, `add gt refs` with `m1`..`m4`; `typecheck.ridgun`; `parser.ridgun`).
- [ ] Decide with the user which patterns become pipelines, and whether a helper or operator is needed where the state is not the last argument (for example `nc emit list st ins sp`).
- [ ] Rewrite in small batches, one file at a time.
- [ ] After each batch, rebuild with a bootstrap and run the full suite and `test parallel and tensors.ridgun` on LLVM and `--target x86_64-elf`. The compiler must stay a fixed point and as fast as before.
## Progress log (append-only, newest last)
- 2026-11-07: Noted at the user's request while working on TASK-0057.
## Files changed (keep current)
-
## Verification performed (command → result, newest last)
-
## Exact next actions
1. Make the candidate list (first step of the plan).
## Decisions / open questions
- Which code-emission chains read better as pipelines, and which must keep the variables (values used twice, guards).
## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
