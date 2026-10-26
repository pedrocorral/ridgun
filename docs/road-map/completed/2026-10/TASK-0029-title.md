---
id: TASK-0029
title: Tensor & LLVM Runtime Optimization Passes (OPT-009..OPT-012)
status: completed
created: 2026-10-26
completed: 2026-10-26
requirements:
  - FR-COMP-004
  - FR-COMP-010
  - FR-COMP-011
tests:
  - TS-UNIT-007
  - TS-FUNC-008
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-011-compiler-optimization-passes-and-tensor-codegen.md
  - docs/etc/compiler_optimizations.md
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - src/test/ridgun/test llvm codegen.rg
  - src/test/ridgun/test parallel and tensors.rg
scope:
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - src/test/ridgun/test llvm codegen.rg
  - docs/requirements/functional/compiler/FR-COMP-011-compiler-optimization-passes-and-tensor-codegen.md
  - docs/etc/compiler_optimizations.md
owner: agent-001
claimed: 2026-10-26T09:27:44Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0029 — Tensor & LLVM Runtime Optimization Passes (`OPT-009`..`OPT-012`)

## Goal (one sentence)
Implement `OPT-009` (unrolled constant-offset frame prologue/epilogue SROA & direct `NCallFn` in `Tensor` maps), `OPT-010` (`!invariant.load !0` on immutable `Tensor` metadata & `noalias` buffer allocators), `OPT-011` (hardware `rep movsb`/`rep stosb`/`rep stosq` & zero-boxing row/col slice/set builtins `92..95`), and `OPT-012` (SIMD-vectorized flat Hadamard `+`, `-`, `*`, `and`, `or`, `xor` and fast cache-friendly 2D `NEinsum` `@__rg_fast_einsum`) in `compiler.rg` and `llvm.rg`.

## Plan
- [x] Implement `OPT-009`..`OPT-012` in `src/main/ridgun/lib/compiler.rg` and `src/main/ridgun/lib/llvm.rg`.
- [x] Add unit tests in `src/test/ridgun/test llvm codegen.rg` and document `OPT-009`..`OPT-012` in `FR-COMP-011` and `docs/etc/compiler_optimizations.md`.
- [x] Bootstrap Stage 1 `target/ridgunc` and Stage 2 `target/ridgunc2` + `target/stable`, verify `40/40` `tests/run.py` and `6/6` `./bin/stable test`, and install into `bin/`.

## Progress log (append-only, newest last)
- 2026-10-26: Implemented `OPT-009`..`OPT-012` in `compiler.rg` and `llvm.rg`; verified `[PASS] test llvm codegen`.
- 2026-10-26: Bootstrapped Stage 1 `target/ridgunc` (2m35s) and Stage 2 `target/ridgunc2` (2m34s) + `target/stable` (8.7s).

## Files changed (keep current)
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/test/ridgun/test llvm codegen.rg`
- `docs/requirements/functional/compiler/FR-COMP-011-compiler-optimization-passes-and-tensor-codegen.md`
- `docs/etc/compiler_optimizations.md`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/ridgunc run "src/test/ridgun/test llvm codegen.rg"` → `[PASS] test llvm codegen`
- `./target/ridgunc run "src/test/ridgun/test parallel and tensors.rg"` → `10,000 x sha256 raw: 3 ms`, `2,000 x blamka p16: 12 ms`, `20 MiB Tensor alloc: 2 ms`, `10,000 x HMAC-SHA256: 7 ms`
- `RIDGUNC=$PWD/target/ridgunc2 python3 tests/run.py` → `40 passed, 0 failed`
- `./bin/stable test` → `6/6 test suite(s) passed`

## Exact next actions
1. Task complete.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
