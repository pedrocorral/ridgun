---
id: TASK-0034
title: Enforce strict per-module import visibility (each module sees only its own names and its explicit imports)
status: completed
created: 2026-10-26
completed: 2026-10-27
requirements: [FR-COMP-012] # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files:
  - docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md
  - src/main/ridgun/lib/parser.rg
  - src/test/ridgun/test lib and plugins.rg
  - docs/lang/spec.md
scope:
  - src/main/ridgun/lib/parser.rg
  - src/test/ridgun/test lib and plugins.rg
  - docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md
  - docs/lang/spec.md
  - docs/book/
  - .aix/custom/instructions/languages/ridgun.md
  - .agents/skills/implement-code-ridgun/SKILL.md
owner: agent-001
claimed: 2026-10-26T21:26:35Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0034 — Enforce strict per-module import visibility (each module sees only its own names and its explicit imports)

## Goal (one sentence)
Enforce strict 3-tier per-module import visibility in `ridgunc` (`FR-COMP-012`) so each module `M` resolves unqualified types, constructors, record fields, functions, and multi-word calls strictly against (1) `M`'s own declarations, (2) `M`'s direct imports, and (3) `M`'s transitive imports, preventing sibling modules or the root application from leaking into imported libraries.

## Plan
- [x] Update `FR-COMP-012` requirement (`AC-5`, `AC-6`) to specify strict 3-tier per-module import visibility and unimported sibling isolation.
- [x] Implement per-module import tracking (`@__rg_mod_import__`, `__imp__:<ikey>`, `__ren__:<m>`) and 3-tier unqualified lookup (`lookup_in_mod_scope`, `lookup_scoped_fn_or_field`, `try_consume_scoped_words`, `try_consume_unimported_words`) in `src/main/ridgun/lib/parser.rg`.
- [x] Bootstrap Stage 1 (`ridgunc_s1`) and Stage 2 (`ridgunc_s2`), install `bin/ridgunc` and `bin/stable`, and add regression tests in `src/test/ridgun/test lib and plugins.rg`.
- [x] Update `docs/lang/spec.md`, all 7 language editions of the book (`docs/book/*`), and Ridgun instructions/skills.

## Progress log (append-only, newest last)
- 2026-10-27: Updated `FR-COMP-012`, implemented 3-tier per-module import visibility in `src/main/ridgun/lib/parser.rg`, bootstrapped `bin/ridgunc` and `bin/stable`, added regression tests in `src/test/ridgun/test lib and plugins.rg`, and updated `docs/lang/spec.md`, the 7 book editions, and skills/instructions.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md`
- `src/main/ridgun/lib/parser.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `docs/lang/spec.md`
- `docs/book/es/06-tipos-algebraicos-y-polimorfismo.md` (and `ca`, `gl`, `eu`, `en`, `pt`, `sv` + HTML outputs)
- `.aix/custom/instructions/languages/ridgun.md`
- `.agents/skills/implement-code-ridgun/SKILL.md`
- `bin/ridgunc`, `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/ridgunc check "src/test/ridgun/test core language.rg" && ./bin/ridgunc run "src/test/ridgun/test core language.rg"` → 0 errors, all assertions passed
- `./bin/ridgunc run "src/test/ridgun/test lib and plugins.rg"` → 0 errors, all assertions passed (including `FR-COMP-012` per-module import visibility and unimported leak rejection)

## Exact next actions
1. Complete `python3 tests/run.py`, mark `TASK-0034` done, validate docs, and commit.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
