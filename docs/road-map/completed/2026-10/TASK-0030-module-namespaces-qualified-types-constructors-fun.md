---
id: TASK-0030
title: Module Namespaces, Qualified Types/Constructors/Functions, and Aliased Imports (FR-COMP-012)
status: completed
created: 2026-10-26
completed: 2026-10-26
requirements:
  - FR-COMP-005
  - FR-COMP-006
  - FR-COMP-012
tests:
  - TS-UNIT-001
  - TS-FUNC-005
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test core language.rg
scope:
  - docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md
  - docs/requirements/functional/compiler/INDEX.md
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test core language.rg
owner: agent-001
claimed: 2026-10-26T12:38:49Z
claimed_by: agent gemini@solarfall
---
# TASK-0030 — Module Namespaces, Qualified Types/Constructors/Functions, and Aliased Imports (`FR-COMP-012`)

## Goal (one sentence)
Implement module-scoped namespaces (`import <mod> [as <alias>]`, `module :: <name>`, `type <Local> = <mod.Type>`, and qualified `mod.Type`, `mod.Ctor`, `mod.Type.Ctor`, `mod.field`, `mod.fn`) across `lexer.rg`, `parser.rg`, `typecheck.rg`, and `compiler.rg` so distinct modules can define identically named types, records, constructors, fields, and functions without collision.

## Plan
- [x] Specify `FR-COMP-012` in `docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md` and update `INDEX.md`.
- [x] Update `lexer.rg`, `parser.rg`, `typecheck.rg`, and `compiler.rg` with `@implements FR-COMP-012` to support dot-qualified identifiers, `import ... as ...`, `module :: ...`, local type aliases, and collision-free module scoping.
- [x] Add comprehensive unit and functional tests in `src/test/ridgun/test core language.rg`.
- [x] Bootstrap `ridgunc` and `stable` (`bin/ridgunc`, `bin/stable`), verify all test suites and `aix docs validate`, and complete `TASK-0030`.

## Progress log (append-only, newest last)
- 2026-10-26: Created `FR-COMP-012` and started `TASK-0030`.
- 2026-10-26: Implemented `FR-COMP-012` across `lexer.rg`, `parser.rg`, `typecheck.rg`, and `compiler.rg`, added tests in `src/test/ridgun/test core language.rg`, bootstrapped Stage 2 `bin/ridgunc` and `bin/stable`, and verified `./bin/stable test` (6/6 passed), `python3 tests/run.py` (40/40 passed), and `aix docs validate` (0 errors).

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/test/ridgun/test core language.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/stable test` → Passed 6/6 test suites — 0 failures.
- `python3 tests/run.py` → 40 of 40 promised behaviours passed.
- `aix docs validate` → 0 errors.

## Exact next actions
- None (`TASK-0030` completed).

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
