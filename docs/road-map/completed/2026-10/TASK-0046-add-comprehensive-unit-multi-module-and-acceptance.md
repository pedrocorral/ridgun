---
id: TASK-0046
title: Add comprehensive unit, multi-module, and acceptance regression tests for edtech-orm bugs
status: completed
created: 2026-10-30
completed: 2026-10-30
requirements: [FR-COMP-014, FR-COMP-012, FR-COMP-007, FR-COMP-009]
tests: [TS-UNIT-001]
security: []
context_files:
  - src/test/ridgun/test core language.rg
  - src/test/ridgun/test lib and plugins.rg
  - tests/cases/names/pipe_into_local_vs_record_field_and_unary_fn.rg
  - tests/cases/functions/syscall_variadic_padding_and_agent_dce.rg
scope:
  - src/test/ridgun/test core language.rg
  - src/test/ridgun/test lib and plugins.rg
  - tests/cases/names/pipe_into_local_vs_record_field_and_unary_fn.rg
  - tests/cases/functions/syscall_variadic_padding_and_agent_dce.rg
owner: agent-001
claimed: 2026-10-30T17:57:46Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only
---
# TASK-0046 — Add comprehensive unit, multi-module, and acceptance regression tests for edtech-orm bugs

## Goal (one sentence)
Expand regression test coverage for all three `edtech-orm` bugs across unit (`test core language.rg`), multi-module/library (`test lib and plugins.rg`), and acceptance (`tests/cases/`) test suites.

## Plan
- [x] Expand unit tests in `src/test/ridgun/test core language.rg` to cover non-terminal vs terminal `expr -> target` (record field getter) and `expr -> tagval` (unary function), chained `mut` pipeline re-bindings, `sys call` with 1, 3, 6, and 7 arguments, and 6-arg `sys call` in both live and DCE-eliminated agent workers.
- [x] Add multi-module and `.rglib` integration tests in `src/test/ridgun/test lib and plugins.rg` (Section 11) covering cross-module `expr -> target` (`json_hlp`) vs `type QueryPlan = target: String` (`orm_hlp`), multi-module mixfix word collision `params` (`sol_hlp` + `orm_hlp` calling `(pred params a) :: (pred params b)`), and 6-arg `sys call` agent workers (`pg_hlp`) in both source and `.rglib` modes.
- [x] Add acceptance test cases `tests/cases/names/pipe_into_local_vs_record_field_and_unary_fn.rg` and `tests/cases/functions/syscall_variadic_padding_and_agent_dce.rg`.

## Progress log (append-only, newest last)
- 2026-10-30: Added unit, multi-module (`.rg` and `.rglib`), and acceptance test cases covering all permutations of the three `edtech-orm` bugs and verified all suites.

## Files changed (keep current)
- `src/test/ridgun/test core language.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `tests/cases/names/pipe_into_local_vs_record_field_and_unary_fn.rg`
- `tests/cases/functions/syscall_variadic_padding_and_agent_dce.rg`

## Verification performed (command → result, newest last)
- `./bin/ridgunc build "src/test/ridgun/test core language.rg" -o target/test_core && ./target/test_core` → all core language tests passed
- `./bin/ridgunc build "src/test/ridgun/test lib and plugins.rg" -o target/test_lib && ./target/test_lib` → all library, multi-module, and `.rglib` tests passed
- `./bin/ridgunc run tests/run.rg --no-toolchain pipe_into_local syscall_variadic` → 2 of 2 promised behaviours passed
- `aix docs validate` → 0 errors, 1 warnings

## Exact next actions
1. Complete `TASK-0046` and commit.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
