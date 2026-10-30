---
id: TASK-0045
title: Fix pipeline terminal local binding (-> var) vs record field/function and @__rg_fn_0 DCE in agent handlers (edtech-orm)
status: completed
created: 2026-10-30
completed: 2026-10-30
requirements: [FR-COMP-014, FR-COMP-012, FR-COMP-007]
tests: [TS-UNIT-001]
security: []
context_files:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/test/ridgun/test core language.rg
scope:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/test/ridgun/test core language.rg
owner: agent-001
claimed: 2026-10-30T15:08:08Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only
---
# TASK-0045 — Fix pipeline terminal local binding (-> var) vs record field/function and @__rg_fn_0 in sys_call (edtech-orm)

## Goal (one sentence)
Fix the `edtech-orm` compilation failures: (1) non-final `expr -> v` pipeline bindings colliding with record field getters or functions when `v` is read later in the block, (2) 6-argument `sys call` falling through to undefined `@__rg_fn_0`, and (3) `str map set` overwriting collided word/symbol map entries with `"__multi__"` when multiple modules define the same mixfix words.

## Plan
- [x] Fix `is pipe var target`, `is scoped pipe var target`, and `is encode pipe var target` in `src/main/ridgun/lib/parser.rg` to bind `v` as a local variable (`StmtLet v expr`) when subsequent statements in the block read `v`.
- [x] Add `str map set` in `src/main/ridgun/lib/parser.rg` so multi-module word/symbol collision maps update existing keys to `"__multi__"`.
- [x] Support variadic/padded `sys_call` in `src/main/ridgun/lib/compiler.rg` and `src/main/ridgun/lib/typecheck.rg` so `< 7` argument `sys call` invocations pad missing arguments with `0` instead of emitting `@__rg_fn_0`.
- [x] Bootstrap `ridgunc` (stage 1 -> stage 2), add regression tests to `src/test/ridgun/test core language.rg`, and verify all `edtech-orm` repros and `aix docs validate`.

## Progress log (append-only, newest last)
- 2026-10-30: Fixed pipeline terminal local variable binding vs record field getter/function collision, `sys_call` argument padding, and `str map set` multi-module word collision tracking; bootstrapped `ridgunc` and verified repros and test suite.

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/test/ridgun/test core language.rg`
- `bin/ridgunc`

## Verification performed (command → result, newest last)
- `./bin/ridgunc build /tmp/ridgun-compiler/2026-10-30/repros/orm1_arrow_into_field_name.rg` → 0 errors, prints `4`
- `bash /tmp/ridgun-compiler/2026-10-30/repros/orm2_undefined_rg_fn_0.sh` → 0 errors, native ELF executable created
- `./bin/ridgunc build "src/test/ridgun/test core language.rg" -o target/test_core && ./target/test_core` → all core language tests passed
- `aix docs validate` → 0 errors, 1 warnings

## Exact next actions
1. Mark task done (`aix task done TASK-0045`) and commit.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
