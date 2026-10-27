---
id: TASK-0036
title: Optimize library compile-time performance and replace Python scripts with Ridgun and Bash
status: completed
created: 2026-10-27
completed: 2026-10-27
requirements: [FR-COMP-004, FR-COMP-012, FR-STABLE-003]
tests: []
security: []
context_files:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
  - build.rg
  - tests/run.rg
  - docs/book/build_book.sh
scope:
  - src/main/ridgun/**
  - src/test/ridgun/**
  - tests/**
  - docs/book/**
  - build.rg
owner: agent-001
claimed: 2026-10-27T12:47:28Z
claimed_by: agent gemini@solarfall
---
# TASK-0036 — Optimize library compile-time performance and replace Python scripts with Ridgun and Bash

## Goal (one sentence)
Eliminate the $\mathcal{O}(N \cdot F \cdot M)$ library/module compilation bottleneck in `parser.rg`, add a library compile-time scaling test, replace `tests/run.py` with a 100% pure Ridgun runner (`tests/run.rg`), and replace `docs/book/build_book.py` with a Bash script (`docs/book/build_book.sh`).

## Plan
- [x] Replace `docs/book/build_book.py` with `docs/book/build_book.sh` and remove `docs/book/build_book.py`.
- [x] Precompute per-module scope tables and prune unreachable imported library functions in `src/main/ridgun/lib/parser.rg` so compiling programs with `.rglib` / `module ::` libraries is fast.
- [x] Replace `tests/run.py` with a pure Ridgun acceptance test runner `tests/run.rg` (including a library compile-time scaling check) and remove `tests/run.py`.
- [x] Bump version to `0.9.22` in `build.rg`, `ridgunc`, and `stable`, bootstrap Stage 1 & Stage 2 binaries, and verify all tests and `aix docs validate`.

## Progress log (append-only, newest last)
- 2026-10-27: Created task to optimize library compile times and eliminate all Python scripts from the repository.
- 2026-10-27: Replaced `docs/book/build_book.py` with `docs/book/build_book.sh` (Bash + `jq`) and verified all 8 book editions (`es`, `ca`, `gl`, `eu`, `en`, `pt`, `sv`, root `index.html`).
- 2026-10-27: Recorded lesson `no-python-scripts-in-repo.md` in `.aix/custom/skills/core/lessons-learnt-notes/lessons/` and synced skills via `aix install`.
- 2026-10-27: Optimized `src/main/ridgun/lib/parser.rg` (`resolve_scoped_state` per-module `special_ff` caching, per-`FnCase` word-set reachability pruning for `.rglib` functions, `filter_arities_for_wset` per-clause arity filtering, `std_builtin_arity` table, and allocation-free prefix checks), reducing `stable/main.rg` check time from 10.1 s to 3.4 s and library-importing program build time to ~220 ms.
- 2026-10-27: Replaced `tests/run.py` with pure Ridgun `tests/run.rg` (with 4 toolchain checks including standard library import build time < 3000 ms), updated `ridgunc run` to forward CLI args and exit status, bootstrapped `bin/ridgunc` and `bin/stable` v0.9.22, and verified 6/6 `stable test` suites and 41/41 `tests/run.rg` acceptance checks.

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `tests/run.rg`
- `tests/README.md`
- `docs/book/build_book.sh`
- `.aix/custom/skills/core/lessons-learnt-notes/lessons/no-python-scripts-in-repo.md`

## Verification performed (command → result, newest last)
- `./docs/book/build_book.sh` → `All books built successfully!` (exit 0)
- `./bin/ridgunc run tests/run.rg` → `41 of 41 promised behaviours passed` (exit 0, including `perf/list_append_and_prepend.rg`, `perf/parallel_agents_not_slower.rg`, and library import build check in ~220 ms)
- `./bin/stable check && ./bin/stable test` → `Checked 14 module(s) — 0 errors; Passed 6/6 test suite(s) — 0 failures` (exit 0)

## Exact next actions
1. Task completed.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
