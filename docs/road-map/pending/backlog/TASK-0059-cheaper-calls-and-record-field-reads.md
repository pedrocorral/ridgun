---
id: TASK-0059
title: Cheaper small calls and record field reads
status: pending             # pending | going-on | blocked | completed
created: 2026-11-08
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files:
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/x86_64.rg
scope:
  - src/main/ridgun/lib/*.rg
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0059 — Cheaper small calls and record field reads

## Goal (one sentence)
Make a record field read and a call to a small non-recursive function cost a few nanoseconds instead of 20-50 ns, without changing behaviour or RMM results.

## Plan
- [ ] Measure the parts of a field read on LLVM and x86-64 (libs `llamadas.rg`, 1M iterations: loop 22 ms, accessor 61 ms, pattern in a helper 68 ms on 0.9.44 LLVM; 61 / 111 / 124 ms on x86-64).
- [ ] Inline fast path for `NAdtField slot idx` with idx >= 0 (read the field, clone it) instead of the runtime call `@__rg_rt_adt_field`; x86-64 the same as an encoded routine.
- [ ] Pass the argument of a leaf accessor borrowed: today the caller clones the record and the accessor drops it (two reference-count updates per read).
- [ ] Evaluate inlining one-line non-recursive functions at the RExpr level (substitution of arguments, CMM drops kept exact).
- [ ] After each step: bootstrap, full suite, `test parallel and tensors.rg` on both backends, no leaks (`cmm live blocks`).

## Progress log (append-only, newest last)
- 2026-11-08: Noted from the libs report `hashmap-tensores-y-campos.md` (point 5, "para evaluar, sin que bloquee"). On LLVM the accessor is already a register function with `inlinehint`; the cost left is the clone of the record in the caller, the opaque runtime call `@__rg_rt_adt_field` (read and clone of the field) and the drop of the argument.

## Files changed (keep current)
-

## Verification performed (command → result, newest last)
-

## Exact next actions
1. Profile one accessor call in the LLVM IR of `llamadas.rg` and write down the cost of each part.

## Decisions / open questions
- Whether borrowed arguments need a new calling mode for the `_reg` functions or a lowering-time rewrite of accessor calls.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
