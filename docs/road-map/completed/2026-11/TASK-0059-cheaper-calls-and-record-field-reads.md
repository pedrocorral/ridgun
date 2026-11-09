---
id: TASK-0059
title: Cheaper small calls and record field reads
status: completed
created: 2026-11-08
completed: 2026-11-09
requirements: [FR-COMP-011]  # FR-*/NFR-* this task delivers or touches
tests: [TS-COMP-011]        # TS-* to automate
security: []                # VUL-* to address
context_files:
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/x86_64.rg
scope:
  - src/main/ridgun/lib/*.rg
owner: agent-002
claimed: 2026-11-08T16:10:59Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0059 — Cheaper small calls and record field reads

## Goal (one sentence)
Make a record field read and a call to a small non-recursive function cost a few nanoseconds instead of 20-50 ns, without changing behaviour or RMM results.

## Plan
- [x] Measure the parts of a field read on LLVM and x86-64 (libs `llamadas.rg`, 1M iterations: loop 22 ms, accessor 61 ms, pattern in a helper 68 ms on 0.9.44 LLVM; 61 / 111 / 124 ms on x86-64).
- [x] Inline fast path for `NAdtField slot idx` with idx >= 0 (read the field, clone it) instead of the runtime call `@__rg_rt_adt_field` (LLVM; OPT-016). x86-64 keeps the runtime routine: the gain there comes from the compiler-level steps.
- [x] Pass the argument of a leaf accessor borrowed (direct field read, OPT-016; borrowed pattern parameters, OPT-018): today the caller clones the record and the accessor drops it (two reference-count updates per read).
- [x] Evaluate inlining one-line non-recursive functions at the RExpr level: not needed. With OPT-015..OPT-018 LLVM inlines the `_reg` functions and the remaining cost was the clone and drop of the argument, which borrowing removes.
- [x] After each step: bootstrap, full suite, `test parallel and tensors.rg` on both backends, no leaks (`cmm live blocks`).

## Progress log (append-only, newest last)
- 2026-11-08: Noted from the libs report `hashmap-tensores-y-campos.md` (point 5, "para evaluar, sin que bloquee"). On LLVM the accessor is already a register function with `inlinehint`; the cost left is the clone of the record in the caller, the opaque runtime call `@__rg_rt_adt_field` (read and clone of the field) and the drop of the argument.

- 2026-11-08: Measured on `llamadas.rg` (1M iterations, LLVM): the empty loop cost 20 ms because every self tail call called `@__rg_rt_tco_copy` and the frame escaped. Steps and results (accessor / pattern / empty loop, ms): 0.9.45 55 / 62 / 20; inline tail-call copy and epilogue 39 / 43 / 3; inline field read 38 / 41 / 3; direct field read 20 / 42 / 3; deferred move of the record in the tail call 3 / 26 / 3; inline constructor match 4 / 21 / 3; borrowed pattern parameters 3 / 6 / 3. x86-64: 111 / 124 / 61 → 62 / 80 / 54.

- 2026-11-09: Incident. The first OPT-018 build made the self-built compiler (stage 2) pass 7 GB in 3 s on `check`; two uncapped runs crashed the machine. Cause: a borrowed call drops its scratch values after it returns, so `lex loop at` -> `lex step` (tail position, mutual recursion) was no longer a tail call; the pending frames kept `rev_acc` alive and `::` copied it every token (quadratic memory: 1 000 rounds 24 MB, 4 000 rounds 321 MB). Fix: `borrow tail fns` excludes every function called in tail position from borrowing. After the fix: stage 2 `check analyzer.rg` 96 MB (installed 0.9.45: 99 MB), self-build 914 MB, s2/s3 differ by 5 bytes; lexer on `analyzer.rg` 18 MB (0.9.45: 20 MB). Rule and incident recorded in `docs/etc/compiler_optimizations.md` ("Rule: tail calls stay last") and as a project lesson (memory caps on every run).

## Files changed (keep current)
- `src/main/ridgun/lib/compiler.rg`: `lower field read`; deferred moves in self tail calls (`tco deferred vars`, `lower tco args deferred`, `lower tco deferred moves`); borrowed parameters (`borrow masks`, `fn borrow mask`, `lower borrow call`, `borrow fn instrs`, tail-position exclusion `borrow tail fns`); getter marks (`env is getter`, `add getter marks`).
- `src/main/ridgun/lib/llvm.rg`: unrolled tail-call copy, prologue and epilogue for frames up to 24 slots; `NClearLocals` unrolled up to 24; `@__rg_adt_field_fast`, `@__rg_match_adt_fast`; `NPeekSlot`, `NForgetSlot`; cache `v0_9_46`.
- `src/main/ridgun/lib/elf64.rg`, `x86_64.rg`, `arm64.rg`: `NPeekSlot`, `NForgetSlot`.
- Version 0.9.46: `build.rg`, `ridgunc/main.rg`, `stable/main.rg`.
- Docs: `docs/etc/compiler_optimizations.md` (OPT-015..OPT-018, ownership contract exception), FR-COMP-011 §7 and AC-4, `tests/README.md`.
- Tests: `tests/cases/functions/borrowed_pattern_parameters.rg`, `tests/cases/functions/tail_call_to_pattern_parameter_function.rg`, `tests/cases/records/field_name_also_a_function.rg`, `tests/cases/perf/field_reads_and_small_calls.rg`.
- Lesson: `.aix/custom/skills/core/lessons-learnt-notes/lessons/cap-memory-and-keep-tail-calls-last.md`.

## Verification performed (command → result, newest last)
All runs capped (`ulimit -v` 3-4 GB, `timeout`).
- Bootstrap bin/ridgunc → s1 → s2 → s3: s2/s3 differ by 5 bytes; s2 `check analyzer.rg` 96 MB (0.9.45: 99 MB); s2 self-build peak 914 MB.
- All 112 cases, LLVM and x86-64 (scratch runner, no `--strict`): only the known failures (4 `strict/` cases that need `--strict`, `rg113` on x86-64).
- `ridgunc run tests/run.rg` with 0.9.46 and its `stable`: 116 of 118; the 2 failures (`stable deps` RG-107, RG-105) fail the same way on 0.9.45 (toolchain script quoting, not this change).
- `test parallel and tensors.rg`: all pass on LLVM and x86-64, 0 heap leaks.
- `tail_call_to_pattern_parameter_function.rg`: passes on 0.9.45 and 0.9.46; fails (no output, crash) with the first OPT-018 build.
- `llamadas.rg` (1M, LLVM): accessor 57 → 4 ms, pattern 63 → 5 ms, empty loop 20 → 3 ms. x86-64: 65 / 85 / 58 ms. `perf/field_reads_and_small_calls.rg`: 123 ms (limit 400).

## Exact next actions
None.

## Decisions / open questions
- Borrowed arguments use a lowering-time rewrite (OPT-018), not a new calling mode for the `_reg` functions.
- Functions called in tail position never borrow (tail calls stay last). Calls between two different functions in tail position are not constant-memory even on 0.9.45 (about 220 bytes per round); that is a separate, pre-existing limit.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
