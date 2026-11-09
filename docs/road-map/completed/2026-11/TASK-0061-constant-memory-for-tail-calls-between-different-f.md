---
id: TASK-0061
title: Constant memory for tail calls between different functions
status: completed
created: 2026-11-09
completed: 2026-11-09
requirements: [FR-COMP-004, FR-COMP-011]
tests: [TS-COMP-011]
security: []                # VUL-* to address
context_files: [docs/etc/compiler_optimizations.md, src/main/ridgun/lib/compiler.rg, src/main/ridgun/lib/llvm.rg, src/main/ridgun/lib/x86_64.rg, tests/cases/functions/tail_call_to_pattern_parameter_function.rg, tests/cases/functions/tail_call_100m.rg]
scope: [src/main/ridgun/lib/compiler.rg, src/main/ridgun/lib/llvm.rg, src/main/ridgun/lib/x86_64.rg, src/main/ridgun/lib/arm64.rg, tests/cases/functions/, docs/etc/compiler_optimizations.md]
owner: agent-002
claimed: 2026-11-09T12:06:47Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0061 — Constant memory for tail calls between different functions

## Goal (one sentence)
Two different functions that call each other in tail position run any number of rounds in constant memory on LLVM and x86-64, as self tail calls already do.

## Plan
- [x] Measure (capped: `ulimit -v 4000000`, `timeout`). Today, even on 0.9.45: `loop tuple` <-> `step tuple` (a tuple passed in tail position) uses 74 MB at 300 000 rounds and 264 MB at 1 200 000; it crashes at 2 000 000 (SIGSEGV; SIGILL at 3 000 000) even with a 1 GB stack. About 220 bytes per round.
- [x] Find where the memory goes: native frames, per-call region or arena use, or the missing frame reuse for `NCallFn` in tail position (only `NTailCall`, self calls, reuses the frame: OPT-002, OPT-015).
- [x] Reuse the frame for calls in tail position to other functions on every backend, without adding work after the call ("Rule: tail calls stay last" in `docs/etc/compiler_optimizations.md`). Record it as a new `OPT-0NN`.
- [x] Test in `tests/cases/functions/`: 3 000 000 mutual rounds under `max-rss-mb: 64`, on both backends.
- [x] Full bootstrap (stage 2 and 3 near a fixed point, stage-2 peak memory compared with the installed compiler), all cases, `src/test/ridgun/test parallel and tensors.rg` on both backends.
- [x] If frame reuse is not feasible, document the limit in FR-COMP-004 instead. (Feasible on LLVM and x86-64; the remaining limits, ARM64 and more than 8 / 32 parameters, are in FR-COMP-004 §3.)

## Progress log (append-only, newest last)
- 2026-11-09: Found during the OPT-018 incident in TASK-0059 (0.9.46). That incident (a drop after a tail call, quadratic memory in the lexer) is fixed by `borrow tail fns`; this task is the separate limit that was already there.

- 2026-11-09: Measured with 0.9.46 (capped): `loop tuple` <-> `step tuple` LLVM 24 MB at 100 000 rounds, 228 MB at 1 200 000, SIGILL at 3 000 000 (456 MB); x86-64 36 MB at 100 000, SIGSEGV at 1 200 000. Cause: a call to another function in tail position was `NCallFn` + `NReturn`, and the epilogue ran after the call. Guards without a self call and unit functions (`()` added after the last call) also lost the tail position.
- 2026-11-09: OPT-019: new instruction `NTailCallFn fid start count slots`. LLVM: `_reg` functions use `tailcc`; teardown then `tail call` + `ret`. First LLVM build still overflowed on unit functions: `opt` proved the callee returns 0 and returned the constant, so the call left tail position; fixed with `weak_odr` linkage on tail-call targets. x86-64: `rg_tco_copy`, frame resize to the callee's size, `rep stosq`, jump past the callee prologue (first build had an off-by-one in the shrink loop: wrong instruction size, crash). ARM64: call + return (no way to run ARM64 here). Version 0.9.47.

## Files changed (keep current)
- `src/main/ridgun/lib/compiler.rg`: `is direct call target` (extracted from `lower tco arg expr`), `NTailCallFn` in `lower tail return expr`, `expr/stmts/guards have direct tail call`, `unit tail call ok`, `add unit marks`, `wrap unit return *` take the arity map, `tail callee slots`, `fill tail call fns`, `add borrow forgets` handles `NTailCallFn`.
- `src/main/ridgun/lib/elf64.rg`: `NTailCallFn Int Int Int Int`.
- `src/main/ridgun/lib/llvm.rg`: `tailcc` on `@__rg_fn_{fid}_reg` and its calls, `NTailCallFn`, `llvm tail teardown`, `emit llvm fn linked`, `emit llvm fn list linked`, `llvm tail targets`; cache `v0_9_47`.
- `src/main/ridgun/lib/x86_64.rg`: `NTailCallFn` size and encoding, `x86 tail fn ok`, `x86 tail fn shift`, `x86 tail fn moves`.
- `src/main/ridgun/lib/arm64.rg`: `NTailCallFn` as call + return.
- Version 0.9.47: `build.rg`, `ridgunc/main.rg`, `stable/main.rg`; `bin/ridgunc`, `bin/stable` (from the bootstrap s3 and its `stable`).
- Tests: `tests/cases/functions/mutual_tail_calls_3m.rg` (new); `src/test/ridgun/test llvm codegen.rg` (`tailcc` strings, OPT-019 checks, stale OPT-015 `NTailCall` expectation fixed).
- Docs: `docs/etc/compiler_optimizations.md` (OPT-019, rule text), FR-COMP-004 §3 and AC-5, FR-COMP-011 §8.

## Verification performed (command → result, newest last)
All runs capped (`RLIMIT_AS` / `ulimit -v` 4 GB, timeout).
- Reproducer 3 000 000 rounds, new compiler: LLVM 8.6 MB / 1.0 s, x86-64 8.6 MB / 1.25 s (0.9.46: crash at 456 / 308 MB). Unit pair 3 000 000 rounds: 8.4 MB on both.
- Bootstrap bin/ridgunc (0.9.46) -> s1 -> s2 -> s3 (0.9.47): s2/s3 differ by 3 bytes. Self-build peak: s1 917 MB, s2 924 MB, s3 925 MB (installed 0.9.46: 917 MB); about 128 s each.
- Stage-2 `check analyzer.rg`: 66.5 MB (0.9.46: 96.6 MB); `check compiler.rg`: 216 MB (0.9.46: 308 MB).
- All 113 cases, LLVM and x86-64, peak RSS checked against `max-rss-mb` (scratch runner, `--strict`): only the known failures (`rg113_int64_literals` on x86-64; three `names/` cases whose expectations need a build without `--strict`), the same as 0.9.46 apart from the new case, which fails on 0.9.46 and passes on 0.9.47.
- `RIDGUNC=target/ridgunc_s3 STABLE=target/stable_candidate ridgunc run tests/run.rg`: 117 of 119; the 2 failures are the `stable deps` harness bugs fixed by TASK-0060 on its own branch.
- `test basics`, `test core language`, `test strings`, `test parallel and tensors`: pass on LLVM and x86-64, 0 heap leaks; `test llvm codegen`: pass. `test cross platform targets` fails with a type error in `lower_sample_prog` on 0.9.46 as well (not this change).

## Exact next actions
None.

## Decisions / open questions
- Whether LLVM `musttail` (with a matching calling convention for `@__rg_fn_N_reg`) or a jump into the callee's body after a frame copy is the better path; x86-64 and ARM64 need their own lowering.
  Decided: `tailcc` + `tail call` on LLVM (guaranteed for any arity up to 8; `musttail` needs identical prototypes), and on x86-64 a frame copy plus a jump past the callee's prologue.
- `tests/run.rg` parses `max-rss-mb` but never checks it, and builds only for LLVM; the new case was checked for memory and on both backends with a scratch runner. Fixing the runner is outside this task's scope.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
