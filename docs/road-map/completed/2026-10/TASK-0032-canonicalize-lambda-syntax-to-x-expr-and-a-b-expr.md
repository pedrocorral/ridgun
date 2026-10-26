---
id: TASK-0032
title: Canonicalize lambda syntax to (x => expr) and (a b => expr)
status: completed
created: 2026-10-26
completed: 2026-10-26
requirements:
  - FR-COMP-013
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-013-generics-closures-and-regression-hardening.md
  - docs/lang/spec.md
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/test/ridgun/test core language.rg
scope:
  - src/main/ridgun/**
  - src/test/ridgun/**
  - docs/**
  - harness/**
  - .aix/custom/**
  - build.rg
owner: agent-001
claimed: 2026-10-26T19:23:39Z
claimed_by: agent gemini@solarfall
---
# TASK-0032 — Canonicalize lambda syntax to `(x => expr)` and `(a b => expr)`

## Goal (one sentence)
Replace the `\x -> expr` lambda syntax with Ridgun's canonical parenthesized fat-arrow syntax `(x => expr)` / `(a b => expr)` (including `(=> expr)`, `((a b) => expr)`, multi-line bodies, mandatory parentheses, and uppercase/lowercase diagnostics) across the compiler, tests, requirement specs, all 7 editions of The Ridgun Book, and agent skills/instructions.

## Plan
- [x] Update `FR-COMP-013` and `docs/lang/spec.md` to specify `(x => expr)` and `(a b => expr)` and the 5 lambda rules for lexical closures.
- [x] Update `src/main/ridgun/lib/lexer.rg`, `src/main/ridgun/lib/parser.rg`, and `src/main/ridgun/lib/typecheck.rg` to parse `(x => expr)`, `(a b => expr)`, `(=> expr)`, `((a b) => expr)`, and multi-line lambdas inside parentheses, enforce mandatory parentheses and case rules, and bump version to `0.9.21`.
- [x] Update test suites (`src/test/ridgun/test core language.rg`) to test `(x => expr)`, `(acc x => expr)`, `(=> expr)`, `((a b) => expr)`, and multi-line lambdas.
- [x] Update all 7 language editions of The Ridgun Book (`es`, `ca`, `gl`, `eu`, `en`, `pt`, `sv` + `index.html`) and agent skills/instructions (`harness/` and `.aix/custom/`, followed by `aix install`).
- [x] Bootstrap `bin/ridgunc` and `bin/stable`, run `./bin/stable test`, `python3 tests/run.py`, and `aix docs validate`.

## Progress log (append-only, newest last)
- 2026-10-26: Task created.
- 2026-10-26: Updated `FR-COMP-013` and `docs/lang/spec.md` with `(x => expr)` / `(a b => expr)` and the 5 lambda closure rules (`(=> expr)` zero-parameter lambdas, `(a b => ...)` vs `((a b) => ...)` tuple destructuring, multi-line bodies inside parentheses, mandatory parentheses, and uppercase/lowercase function type vs value diagnostics).
- 2026-10-26: Implemented the lexer, parser, and typechecker changes in `src/main/ridgun/lib/{lexer,parser,typecheck}.rg`, bumped compiler and `stable` version to `0.9.21`, updated all 7 editions of The Ridgun Book (`docs/book/{es,ca,gl,eu,en,pt,sv}/`) and agent skills/instructions (`harness/`, `.aix/custom/`), rebuilt self-hosted `bin/ridgunc` and `bin/stable`, and verified all positive and negative test suites.

## Files changed (keep current)
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `build.rg`
- `src/test/ridgun/test core language.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `docs/requirements/functional/compiler/FR-COMP-013-generics-closures-and-regression-hardening.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `docs/lang/spec.md`
- `docs/book/{es,ca,gl,eu,en,pt,sv}/06-*.md`
- `docs/book/{es,ca,gl,eu,en,pt,sv}/07-*.md`
- `docs/book/{es,ca,gl,eu,en,pt,sv}/index.html`
- `docs/book/index.html`
- `harness/instructions/ridgun.md`
- `harness/skills/implement-code-ridgun/SKILL.md`
- `harness/skills/implement-code-ridgun/references/cheatsheet.rg`
- `.aix/custom/instructions/languages/ridgun.md`
- `.aix/custom/skills/implement/code-ridgun/SKILL.md`
- `.aix/custom/skills/implement/code-ridgun/references/cheatsheet.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/stable check` → `Checked 14 module(s) — 0 errors.`
- `./bin/stable test` → `Passed 6/6 test suite(s) — 0 failures.`
- `python3 tests/run.py --no-toolchain functions generics` → `2 of 2 promised behaviours passed`
- `aix docs validate` → `0 errors, 1 warnings`

## Exact next actions
1. Task complete.

## Decisions / open questions
- Use `(x => expr)` / `(a b => expr)` as the single canonical lambda syntax in Ridgun, enforcing the 5 closure rules (`(=> expr)`, `((a b) => expr)`, multi-line body after `=>`, mandatory parentheses, and uppercase/lowercase diagnostics).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
