---
id: TASK-0039
title: Fix RG-102 local prefix underscore shadowing and RG-055 first-class builtin functions
status: completed
created: 2026-10-27
completed: 2026-10-27
requirements:
  - FR-COMP-002
  - FR-COMP-005
tests:
  - TS-COMP-001
  - TS-COMP-002
  - TS-COMP-007
security: []
context_files:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/compiler.rg
  - tests/run.rg
scope:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
  - src/test/ridgun/test lib and plugins.rg
  - build.rg
  - tests/**
owner: agent-001
claimed: 2026-10-27T19:02:15Z
claimed_by: agent gemini@solarfall
---
# TASK-0039 — Fix RG-102 local prefix underscore shadowing and RG-055 first-class builtin functions

## Goal (one sentence)
Fix the `RG-102` regression where a parameter or local variable `x` prevents underscore encoding on functions starting with `x_`, and fix `RG-055` so built-in functions passed by name to higher-order functions (`map`, `||map`, `filter`, `||filter`, `fold`, `agent`, user HOFs) execute properly instead of returning `()`.

## Plan
- [x] Fix `should encode base underscores`, `is encode pipe var target`, and `lookup var arity` in `src/main/ridgun/lib/parser.rg` so a local/parameter `x` never suppresses underscore encoding on `x_*` function names (`RG-102`).
- [x] Synthesize first-class dispatch wrappers in `src/main/ridgun/lib/compiler.rg` for built-in functions referenced as values (`EVar`) or partial applications (`RG-055`), and add missing entries in `std builtin arity` (`src/main/ridgun/lib/parser.rg`).
- [x] Add regression tests in `tests/cases/names/param_prefix_does_not_hide_underscore_fn.rg` and `tests/cases/functions/builtin_passed_to_map.rg`.
- [x] Bump version to `0.9.25`, bootstrap Stage 1 & Stage 2 `bin/ridgunc` and `bin/stable` with `--strict`, and verify all test suites and `aix docs validate`.

## Progress log (append-only, newest last)
- 2026-10-27: Created and claimed `TASK-0039` (`agent-001`), pinpointed root causes of `RG-102` (`parser.rg:5323`) and `RG-055` (`compiler.rg` dispatch table missing built-in function wrappers).
- 2026-10-27: Fixed `should encode base underscores`, `is encode pipe var target`, and `lookup var arity` in `src/main/ridgun/lib/parser.rg`; added `collect builtin val fndefs` and `build builtin wrapper fndefs` in `src/main/ridgun/lib/compiler.rg`; added regression tests in `tests/cases/names/param_prefix_does_not_hide_underscore_fn.rg` and `tests/cases/functions/builtin_passed_to_map.rg`; bootstrapped `ridgunc` & `stable` `v0.9.25` and verified all suites green.

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `bin/ridgunc`
- `bin/stable`
- `tests/cases/names/param_prefix_does_not_hide_underscore_fn.rg`
- `tests/cases/functions/builtin_passed_to_map.rg`

## Verification performed (command → result, newest last)
- `./bin/ridgunc build --strict src/main/ridgun/ridgunc/main.rg -o target/ridgunc_stage1 && ./target/ridgunc_stage1 build --strict src/main/ridgun/ridgunc/main.rg -o target/ridgunc_stage2` → Stage 1 & Stage 2 `ridgunc` v0.9.25 built cleanly.
- `./bin/stable check` → `14/14` modules, `0 errors`.
- `./bin/stable test` → `6/6` suites passed, `0 failures`.
- `./bin/ridgunc run tests/run.rg` → `54/54` promised behaviours passed.
- `aix docs validate` → `0 errors`.

## Exact next actions
1. Close task with `aix task done TASK-0039`.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
