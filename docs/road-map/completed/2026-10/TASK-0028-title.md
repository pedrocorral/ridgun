---
id: TASK-0028
title: "LLVM IR Register Fast-Paths for NBinOp, Slot Ops, 64-Bit U64 Boxing, and str_char_at (v0.9.20)"
status: completed
created: 2026-10-25
completed: 2026-10-25
requirements:
  - FR-COMP-004
  - FR-COMP-010
  - FR-COMP-011
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-011-compiler-optimization-passes-and-tensor-codegen.md
  - docs/etc/compiler_optimizations.md
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test llvm codegen.rg
scope:
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
  - src/test/ridgun/test llvm codegen.rg
  - src/test/ridgun/test lib and plugins.rg
  - build.rg
  - docs/requirements/functional/compiler/FR-COMP-011-compiler-optimization-passes-and-tensor-codegen.md
  - docs/etc/compiler_optimizations.md
owner: agent-001
claimed: 2026-10-25T16:43:18Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0028 — LLVM IR Register Fast-Paths for NBinOp, Slot Ops, 64-Bit U64 Boxing, and str_char_at (v0.9.20)

## Goal (one sentence)
Implement inline LLVM IR fast-paths for `NBinOp`, local slot operations (`NCloneSlot`, `NStoreSlot`, `NRebindSlot`, `NCmmDropSlot`, `NDropVal`, `NAsBool`), `str_char_at` (`NCallBuiltin 40` and `NCallBuiltin 91`), and full 64-bit `U64` heap boxing (`0x8000000000000000` header in `@__rg_box_i64`) with `opt -O2` + `llc -O2` register promotion in `ridgunc` v0.9.20.

## Plan
- [x] Implement `@__rg_box_i64_slow` with `-9223372036854775808` (`0x8000000000000000`) `U64` heap tag and update `@__rg_match_heap_tag`, `@__rg_not_op`, and `@__rg_bin_op_u64_or_slow` for full 64-bit `U64` support.
- [x] Implement inline LLVM IR fast-paths for `NBinOp`, `NCloneSlot`, `NStoreSlot`, `NRebindSlot`, `NCmmDropSlot`, `NDropVal`, and `NAsBool`, plus `opt -O2` pass before `llc -O2`.
- [x] Implement `NCallBuiltin 91` (`@__rg_str_char_at_fast`) for borrowed local `String` variables in `compiler.rg` and `@__rg_builtin_str_char_at` (`NCallBuiltin 40`) in `llvm.rg`.
- [x] Bump version to `0.9.20`, self-host `ridgunc` and `stable` through Stage 3, and verify `40/40` `tests/run.py` and `6/6` `./bin/stable test`.

## Progress log (append-only, newest last)
- 2026-10-25: Implemented `OPT-008` in `src/main/ridgun/lib/llvm.rg` and `src/main/ridgun/lib/compiler.rg`; added unit tests in `src/test/ridgun/test llvm codegen.rg`; bootstrapped `ridgunc` 0.9.20 and `stable` 0.9.20; verified `40/40` `tests/run.py` and `6/6` `./bin/stable test`.

## Files changed (keep current)
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test llvm codegen.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `docs/requirements/functional/compiler/FR-COMP-011-compiler-optimization-passes-and-tensor-codegen.md`
- `docs/etc/compiler_optimizations.md`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `RIDGUNC=$PWD/target/ridgunc python3 tests/run.py` → `40 of 40 promised behaviours passed`
- `./bin/stable test` → `[success] Passed 6/6 test suite(s) — 0 failures.` (`2,000 x blamka p16` = 16,000 BlaMka G rounds in `13–16 ms`; `20 MiB` 2D Tensor allocation in `1–2 ms`; `10,000 x HMAC-SHA256` in `5–6 ms`)

## Exact next actions
1. Mark `TASK-0028` done and validate docs.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
