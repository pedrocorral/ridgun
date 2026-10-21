---
id: TASK-0007
title: Implement shared ADT constructors, expand type, and automatic fn clause merging
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
  - src/main/ridgun/lib/formatter.rg
  - src/test/ridgun/test_core_language.rg
scope:
  - src/main/ridgun/lib/**
  - src/main/ridgun/stable/main.rg
  - src/test/ridgun/test_core_language.rg
  - docs/**
  - harness/**
owner: agent-001
claimed: 2026-10-21T10:57:40Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0007 — Implement shared ADT constructors, expand type, and automatic fn clause merging

## Goal (one sentence)
Deliver `FR-COMP-005`: shared ADT constructor names across multiple `type` definitions, open type extensions (`expand type`), and automatic `fn ::` / `op ::` clause merging before catch-all `_` fallbacks.

## Plan
- [x] Create and approve `FR-COMP-005`.
- [x] Update `formatter.rg`, `parser.rg`, and `typecheck.rg` with `@implements FR-COMP-005`.
- [x] Optimize `elf64.rg` (`hex_to_bytes_range` / `str_to_bytes_range`) to $O(N \log N)$ and rebuild `target/ridgunc` and `target/stable`.
- [x] Add automated tests (`@tests FR-COMP-005`) to `src/test/ridgun/test_core_language.rg` and update docs & `harness/`.

## Progress log (append-only, newest last)
- 2026-10-21: Implemented `FR-COMP-005` in `parser.rg`, `typecheck.rg`, and `formatter.rg`; optimized `elf64.rg` `hex_to_bytes` / `str_to_bytes`; rebuilt `target/ridgunc` and `target/stable`; verified 13/13 modules and 4/4 test suites pass.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `src/main/ridgun/lib/formatter.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/elf64.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test_core_language.rg`
- `docs/lang/spec.md`
- `harness/instructions/ridgun.md`
- `harness/skills/implement-code-ridgun/SKILL.md`
- `harness/skills/implement-code-ridgun/references/cheatsheet.rg`

## Verification performed (command → result, newest last)
- `./target/stable check` → `Checked 13 module(s) — 0 errors.`
- `./target/stable test` → `Passed 4/4 test suite(s) — 0 failures.`

## Exact next actions
1. Mark task done and commit.

## Decisions / open questions
- None (`expand fn` was omitted in favor of automatic `fn ::` clause merging per user request).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
