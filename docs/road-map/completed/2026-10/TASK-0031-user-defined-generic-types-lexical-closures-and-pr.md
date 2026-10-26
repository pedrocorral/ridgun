---
id: TASK-0031
title: User-defined generic types, lexical closures, and production regression hardening (FR-COMP-013)
status: completed
created: 2026-10-26
completed: 2026-10-26
requirements:
  - FR-COMP-013
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-013-generics-closures-and-regression-hardening.md
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/cli.rg
  - .stable/deps/ridgun-libs/src/main/ridgun/lib/str.rg
scope:
  - docs/requirements/functional/compiler/**
  - docs/lang/spec.md
  - .aix/custom/instructions/languages/ridgun.md
  - harness/instructions/ridgun.md
  - src/main/ridgun/**
  - src/test/ridgun/**
  - .stable/deps/ridgun-libs/**
  - tests/cases/**
owner: agent-001
claimed: 2026-10-26T14:37:47Z
claimed_by: agent gemini@solarfall
---
# TASK-0031 — User-defined generic types, lexical closures, and production regression hardening (FR-COMP-013)

## Goal (one sentence)
Deliver user-defined generic ADTs & records (`type Result T E`, `type Page T`), lexical closures (`\x -> expr`), cross-arena agent memory reclamation (`RG-069`), built-in `Option A` (`RG-062`), transitive subdirectory imports (`RG-025`), tail-recursive `str split` (`RG-091`), runtime image caching, and a regression battery (`FR-COMP-013`).

## Plan
- [x] Steg 0: Author `FR-COMP-013` and update `docs/requirements/functional/compiler/INDEX.md`, `docs/lang/spec.md`, `.aix/custom/instructions/languages/ridgun.md`, and `harness/instructions/ridgun.md`.
- [x] Steg 1: Fix `RG-069` (zero cross-arena agent memory leak in `compiler.rg`), `RG-025` (transitive subdirectory imports in `parser.rg`), `RG-091` (tail-recursive `str split` in `str.rg`), and `RG-062` (built-in `Option A = Some A | None`).
- [x] Steg 2: Implement user-defined generic Sum ADTs & Product Records (`type Name A B = ...`) and anonymous lexical closures (`\x -> expr`, `\x y -> expr`).
- [x] Steg 3: Cache static `.rt` runtime image and linker script in `/tmp` for fast `ridgunc` and `stable` compilation.
- [x] Steg 4: Add regression tests in `src/test/ridgun/test core language.rg`, rebuild self-hosted `bin/ridgunc` and `bin/stable`, and verify all suites pass.

## Progress log (append-only, newest last)
- 2026-10-26: Created `FR-COMP-013` and started `TASK-0031`. Diagnosed exact root cause of `RG-069`: cross-thread producer/consumer allocations hash to different `rsp >> 17 & 15` arenas.
- 2026-10-26: Implemented Steg 0–4 across `parser.rg`, `typecheck.rg`, `compiler.rg`, `llvm.rg`, `str.rg`, and `test core language.rg`. Rebuilt self-hosted `bin/ridgunc` and `bin/stable`. Verified `./bin/stable test` (6/6 passed), `python3 tests/run.py` (40/40 passed), `leak_modes.rg` (flat 6,296–6,300 KB RSS across 50,000 messages in all 4 agent modes), and `aix docs validate` (0 errors).

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-013-generics-closures-and-regression-hardening.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `docs/lang/spec.md`
- `.aix/custom/instructions/languages/ridgun.md`
- `harness/instructions/ridgun.md`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/llvm.rg`
- `.stable/deps/ridgun-libs/src/main/ridgun/lib/str.rg`
- `.stable/deps/ridgun-libs/target/bundles/str.rglib`
- `src/test/ridgun/test core language.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `aix task start TASK-0031` -> claimed by `agent-001`
- `./bin/stable test` -> `Passed 6/6 test suite(s) — 0 failures`
- `python3 tests/run.py` -> `40 of 40 promised behaviours passed`
- `aix docs validate` -> `0 errors, 1 warnings`

## Exact next actions
1. Complete `TASK-0031` (`aix task done TASK-0031`) and update `STATE.md`.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
