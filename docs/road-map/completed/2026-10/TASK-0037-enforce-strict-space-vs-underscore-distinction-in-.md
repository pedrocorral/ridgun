---
id: TASK-0037
title: Enforce strict space vs underscore distinction in function names and calls across compiler, libraries, and tests
status: completed
created: 2026-10-27
completed: 2026-10-27
requirements: [FR-COMP-005, FR-COMP-008]
tests: []
security: []
context_files:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
  - tests/run.rg
scope:
  - src/main/ridgun/**
  - src/test/ridgun/**
  - tests/**
  - docs/**
  - .aix/custom/**
owner: agent-001
claimed: 2026-10-27T15:36:28Z
claimed_by: agent gemini@solarfall
---
# TASK-0037 — Enforce strict space vs underscore distinction in function names and calls across compiler, libraries, and tests

## Goal (one sentence)
Ensure `" "` and `"_"` never resolve to the same function name in Ridgun (`fn :: a b` is distinct from `fn :: a_b`), enforce in `--strict` mode that no function declaration or call (including built-ins) contains `_` while variables always allow `_`, migrate all codebase calls to natural spaces, and add regression tests.

## Plan
- [x] Update `FR-COMP-005`, `.aix/custom/instructions/languages/ridgun.md`, and `implement-code-ridgun` skill to specify that `" "` != `"_"` in function names, `--strict` forbids `_` in all function declarations and calls (including built-ins), and variables always permit `_`.
- [x] Migrate all function calls in `src/main/ridgun/**`, `src/test/ridgun/**`, `tests/run.rg`, `tests/cases/**`, and `ridgun-libs` from `foo_bar` to `foo bar` (and eliminate all `_ = expr` statements).
- [x] Update `src/main/ridgun/lib/parser.rg` and `src/main/ridgun/lib/typecheck.rg` so multi-word function names do not collide with `_`-separated single-word names (`" "` != `"_"`), and `--strict` rejects `_` in function calls as well as declarations while allowing `_` in variables.
- [x] Add acceptance test cases in `tests/cases/` verifying that `fn :: foo bar` called as `foo_bar` (and `fn :: foo_bar` called as `foo bar`) fails to compile, and that `--strict` rejects `_` in function calls while allowing `_` in variables.

## Progress log (append-only, newest last)
- 2026-10-27: Created and claimed `TASK-0037`; recorded lesson `space-never-equals-underscore-in-fn-names.md`.
- 2026-10-27: Updated `FR-COMP-005`, `.aix/custom/instructions/languages/ridgun.md`, and `.aix/custom/skills/implement/code-ridgun/SKILL.md`.
- 2026-10-27: Migrated all function and built-in calls across `src/main/ridgun/**`, `src/test/ridgun/**`, `tests/run.rg`, and `tests/cases/**/*.rg` to space-separated names with zero `_ = expr` statements.
- 2026-10-27: Implemented literal underscore encoding (`__U__`) in `src/main/ridgun/lib/parser.rg` so `" "` and `"_"` never resolve to the same function name, and updated `check strict tokens` in `src/main/ridgun/lib/typecheck.rg` to reject `_` in function and built-in calls under `--strict` while permitting `_` in variables and record fields.
- 2026-10-27: Added 5 regression test cases in `tests/cases/names/` and `tests/cases/strict/`, bootstrapped Stage 1 & Stage 2 `bin/ridgunc` and `bin/stable` v0.9.23 under `--strict`, and verified all test suites.

## Files changed (keep current)
- `.aix/custom/skills/core/lessons-learnt-notes/lessons/space-never-equals-underscore-in-fn-names.md`
- `.aix/custom/skills/core/lessons-learnt-notes/SKILL.md`
- `.aix/custom/instructions/languages/ridgun.md`
- `.aix/custom/skills/implement/code-ridgun/SKILL.md`
- `docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md`
- `build.rg`
- `src/main/ridgun/lib/*.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/*.rg`
- `tests/run.rg`, `tests/README.md`, `tests/cases/**/*.rg`
- `bin/ridgunc`, `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/stable check` → `Checked 14 module(s) — 0 errors.`
- `./bin/stable test` → `Passed 6/6 test suite(s) — 0 failures.`
- `./bin/ridgunc run tests/run.rg` → `46 of 46 promised behaviours passed`
- `aix docs validate` → `0 errors, 1 warnings`

## Exact next actions
1. Completed.

## Decisions / open questions
- Confirmed by user:
  1. `" "` != `"_"` always (declaring `fn :: report build status` and calling `report_build_status` must not compile).
  2. In `--strict` mode, `_` is forbidden in all function declarations and calls (including built-ins like `str len`, `int to str`, `read file`), while `_` is ALWAYS allowed in variables (`input_path`, `strict_mode`, `a_i`).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
