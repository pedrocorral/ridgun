---
id: TASK-0041
title: Enforce lowercase logical operators, global stdlib import fallback, and accurate skill tables
status: completed
created: 2026-10-27
completed: 2026-10-28
requirements:
  - FR-COMP-003
  - FR-COMP-006
  - FR-VM-002
tests:
  - TS-COMP-003
  - TS-COMP-006
security: []
context_files:
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - .aix/custom/skills/implement/code-ridgun/SKILL.md
  - .aix/custom/instructions/languages/ridgun.md
scope:
  - src/main/ridgun/
  - src/test/ridgun/
  - tests/cases/logic/
  - .aix/custom/skills/implement/code-ridgun/SKILL.md
  - .aix/custom/instructions/languages/ridgun.md
  - build.rg
  - bin/ridgunc
  - bin/stable
owner: agent-001
claimed: 2026-10-27T20:58:16Z
claimed_by: agent gemini@solarfall
---
# TASK-0041 — Enforce lowercase logical operators, global stdlib import fallback, and accurate skill tables

## Goal (one sentence)
Reject uppercase `AND`, `OR`, `XOR`, `NOT` in `lexer.rg` per `FR-COMP-003 §4`, enable `ridgunc` to resolve standard library imports (`import str`, `import io`, `import posix`, etc.) outside project directories via `~/.local/lib/ridgun`, and separate compiler built-ins from imported standard library functions in `implement-code-ridgun/SKILL.md` (`v0.9.27`).

## Plan
- [x] Migrate internal uppercase `AND`, `OR`, `NOT` in `src/main/ridgun/` and `src/test/ridgun/` to lowercase `and`, `or`, `not`, and remove uppercase `"AND"`, `"OR"`, `"XOR"`, `"NOT"` from `classify word` in `src/main/ridgun/lib/lexer.rg`.
- [x] Add negative regression test `tests/cases/logic/uppercase_and_fails.rg`.
- [x] Add fallback stdlib search paths (`$HOME/.local/lib/ridgun`, `$HOME/.stable/deps`, `/home/boogie/ridgun/ridgun/.stable/deps`) in `resolve rglib bundle raw` (`src/main/ridgun/lib/parser.rg`), install `.stable/deps/*.rglib` into `~/.local/lib/ridgun/`, and add a test running `ridgunc run` from `/tmp` with `import str`, `import io`, and `import posix`.
- [x] Update `.aix/custom/skills/implement/code-ridgun/SKILL.md` and `.aix/custom/instructions/languages/ridgun.md` (`v0.9.27`) so Section 6 clearly separates compiler built-ins (no `import`) from `import str`, `import io`, and `import posix` functions with exact signatures.
- [x] Bump version to `0.9.27`, bootstrap `ridgunc` and `stable`, and run all verification suites.

## Progress log (append-only, newest last)
- 2026-10-27: Created `TASK-0041`.
- 2026-10-28: Migrated uppercase `AND`/`OR`/`NOT` to lowercase across compiler and test `.rg` files, removed uppercase logical operator tokens in `lexer.rg`, added `stdlib deps bases` fallback in `parser.rg`, updated `implement-code-ridgun/SKILL.md` (`v0.9.27`), added `logic/uppercase_and_fails.rg` and `strings/stdlib_imports_outside_project.rg`, bootstrapped `ridgunc` and `stable` `v0.9.27`, and verified all test suites.

## Files changed (keep current)
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/lib/formatter.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test.rg`
- `src/test/ridgun/test llvm codegen.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `tests/run.rg`
- `tests/cases/logic/uppercase_and_fails.rg`
- `tests/cases/strings/stdlib_imports_outside_project.rg`
- `.aix/custom/skills/implement/code-ridgun/SKILL.md`
- `.aix/custom/instructions/languages/ridgun.md`
- `build.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/stable check` → `Checked 14 module(s) — 0 errors.`
- `./bin/stable test` → `Passed 6/6 test suite(s) — 0 failures.`
- `./bin/ridgunc run tests/run.rg` → `56 of 56 promised behaviours passed`

## Exact next actions
1. Task complete.

## Decisions / open questions
- User confirmed that standard library functions (`str trim`, `file exists`, `posix readlink`, etc.) require explicit `import` (`import str`, `import io`, `import posix`), as in most languages, and the skill table should specify their module imports while `ridgunc` resolves standard library imports globally even outside a project.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
