---
id: TASK-0008
title: Support type-name variants without redundant constructor names in type and expand type
status: completed
created: 2026-10-21
completed: 2026-10-21
requirements:
  - FR-COMP-005
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
  - src/test/ridgun/test_core_language.rg
scope:
  - src/main/ridgun/lib/**
  - src/test/ridgun/test_core_language.rg
  - docs/**
  - harness/**
owner: agent-001
claimed: 2026-10-21T11:30:00Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0008 — Support type-name variants without redundant constructor names in type and expand type

## Goal (one sentence)
Support bare type-name variants (`type Something = String | Int | MyStruct Float Int` and `expand type Something = Bool`) without redundant `Int Int` / `String String` constructor names, allowing both bare values and typed patterns `(String s)` / `(Int n)`.

## Plan
- [x] Update `FR-COMP-005` with AC-4 (Type-Name Variants Without Redundant Constructor Names).
- [x] Update `parser.rg`, `typecheck.rg`, `compiler.rg`, `x86_64.rg`, and `arm64.rg`.
- [x] Bootstrap Stage 1 & Stage 2 `target/ridgunc` and `target/stable`.
- [x] Add automated tests to `src/test/ridgun/test_core_language.rg` and update docs & `harness/`.

## Progress log (append-only, newest last)
- 2026-10-21: Implemented bare type-name variants in `parser.rg`, `typecheck.rg`, `compiler.rg`, `x86_64.rg`, and `arm64.rg`; rebuilt `target/ridgunc` and `target/stable`; verified 13/13 modules and 4/4 test suites pass.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/arm64.rg`
- `src/test/ridgun/test_core_language.rg`
- `docs/lang/spec.md`
- `harness/instructions/ridgun.md`
- `harness/skills/implement-code-ridgun/SKILL.md`

## Verification performed (command → result, newest last)
- `./target/stable check` → `Checked 13 module(s) — 0 errors.`
- `./target/stable test` → `Passed 4/4 test suite(s) — 0 failures.`

## Exact next actions
1. Complete `TASK-0008` and commit.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
