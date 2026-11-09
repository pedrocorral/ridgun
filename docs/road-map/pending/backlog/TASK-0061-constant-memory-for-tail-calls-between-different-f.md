---
id: TASK-0061
title: Constant memory for tail calls between different functions
status: pending             # pending | going-on | blocked | completed
created: 2026-11-09
completed:
requirements: [FR-COMP-004, FR-COMP-011]
tests: [TS-COMP-011]
security: []                # VUL-* to address
context_files: [docs/etc/compiler_optimizations.md, src/main/ridgun/lib/compiler.rg, src/main/ridgun/lib/llvm.rg, src/main/ridgun/lib/x86_64.rg, tests/cases/functions/tail_call_to_pattern_parameter_function.rg, tests/cases/functions/tail_call_100m.rg]
scope: [src/main/ridgun/lib/compiler.rg, src/main/ridgun/lib/llvm.rg, src/main/ridgun/lib/x86_64.rg, src/main/ridgun/lib/arm64.rg, tests/cases/functions/, docs/etc/compiler_optimizations.md]
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0061 — Constant memory for tail calls between different functions

## Goal (one sentence)
Two different functions that call each other in tail position run any number of rounds in constant memory on LLVM and x86-64, as self tail calls already do.

## Plan
- [ ] Measure (capped: `ulimit -v 4000000`, `timeout`). Today, even on 0.9.45: `loop tuple` <-> `step tuple` (a tuple passed in tail position) uses 74 MB at 300 000 rounds and 264 MB at 1 200 000; it crashes at 2 000 000 (SIGSEGV; SIGILL at 3 000 000) even with a 1 GB stack. About 220 bytes per round.
- [ ] Find where the memory goes: native frames, per-call region or arena use, or the missing frame reuse for `NCallFn` in tail position (only `NTailCall`, self calls, reuses the frame: OPT-002, OPT-015).
- [ ] Reuse the frame for calls in tail position to other functions on every backend, without adding work after the call ("Rule: tail calls stay last" in `docs/etc/compiler_optimizations.md`). Record it as a new `OPT-0NN`.
- [ ] Test in `tests/cases/functions/`: 3 000 000 mutual rounds under `max-rss-mb: 64`, on both backends.
- [ ] Full bootstrap (stage 2 and 3 near a fixed point, stage-2 peak memory compared with the installed compiler), all cases, `src/test/ridgun/test parallel and tensors.rg` on both backends.
- [ ] If frame reuse is not feasible, document the limit in FR-COMP-004 instead.

## Progress log (append-only, newest last)
- 2026-11-09: Found during the OPT-018 incident in TASK-0059 (0.9.46). That incident (a drop after a tail call, quadratic memory in the lexer) is fixed by `borrow tail fns`; this task is the separate limit that was already there.

## Files changed (keep current)
-

## Verification performed (command → result, newest last)
-

## Exact next actions
1. Build the `loop tuple` / `step tuple` pair with 0.9.46 and measure peak memory at 100 000, 300 000 and 1 200 000 rounds on both backends.

## Decisions / open questions
- Whether LLVM `musttail` (with a matching calling convention for `@__rg_fn_N_reg`) or a jump into the callee's body after a frame copy is the better path; x86-64 and ARM64 need their own lowering.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
