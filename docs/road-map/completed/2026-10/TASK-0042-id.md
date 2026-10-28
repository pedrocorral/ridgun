---
id: TASK-0042
title: Document and implement safe codegen optimizations (OPT-013 register calling convention, OPT-014 HOF specialization) and RMM evolution notes
status: completed
priority: high
created: 2026-10-28
updated: 2026-10-28
assigned_to: null
context_files:
  - docs/etc/compiler_optimizations.md
  - docs/requirements/functional/compiler/FR-COMP-011-compiler-optimization-passes-and-tensor-codegen.md
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test llvm codegen.rg
implements:
  - FR-COMP-002
  - FR-COMP-004
  - FR-COMP-011
owner: agent-001
claimed: 2026-10-28T09:05:03Z
claimed_by: agent gemini@solarfall
---
# TASK-0042 — Document and implement safe codegen optimizations (`OPT-013`, `OPT-014`) and RMM evolution notes

## Goal
1. Document `OPT-013` (Direct SSA Register Calling Convention `@__rg_fn_{fid}_reg` & Caller Frame Escape Elimination), `OPT-014` (AST-Level `fold` / `map` / `filter` Direct-Call Specialization), and the **RMM1 / RMM2 Invariants & Future RMM Evolution Guide** in `docs/etc/compiler_optimizations.md` and `FR-COMP-011` before modifying code.
2. Implement `OPT-013` in `src/main/ridgun/lib/llvm.rg` and `src/main/ridgun/lib/compiler.rg` so direct calls (`NCallFn`) to user functions pass arguments in hardware registers (`@__rg_fn_{fid}_reg`) without escaping caller `%frame` pointers, enabling cross-function LLVM `SROA` and `CGSCC` inlining while preserving `@__rg_fn_{fid}(ptr %args)` for indirect/runtime dispatch.
3. Implement `OPT-014` in `src/main/ridgun/lib/compiler.rg` so `fold`, `map`, and `filter` with known top-level functions or lambdas compile to specialized direct-call helpers rather than indirect runtime closure dispatch (`NCallIndirect1` / `NCallIndirect2`).
4. Add unit/codegen tests in `src/test/ridgun/test llvm codegen.rg`, bootstrap `ridgunc` and `stable` (`v0.9.28`), and verify all test suites.

## Steps
- [x] Document `OPT-013`, `OPT-014`, and RMM1/RMM2 future evolution invariants in `docs/etc/compiler_optimizations.md` and `FR-COMP-011`.
- [x] Implement `OPT-013` (`@__rg_fn_{fid}_reg`) in `llvm.rg` and `compiler.rg`.
- [x] Implement `OPT-014` (`fold` / `map` / `filter` direct-call specialization) in `compiler.rg`.
- [x] Add tests in `src/test/ridgun/test llvm codegen.rg`, rebuild `ridgunc` and `stable` (`v0.9.28`), and verify `stable check`, `stable test`, `tests/run.rg`, and `aix docs validate`.
