---
id: TASK-0016
title: Implement smart compile-time strategy selection for || DAG blocks, ||map/||filter, and Agents (green threads vs OS kernel threads)
status: completed
created: 2026-10-22
completed: 2026-10-22
requirements:
  - FR-COMP-001
  - FR-COMP-009
tests:
  - TS-FUNC-001
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test parallel and tensors.rg
  - README.md
  - docs/book/build_book.py
scope:
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test parallel and tensors.rg
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - README.md
  - docs/book/
owner: agent-001
claimed: 2026-10-22T18:26:26Z
claimed_by: agent gemini@solarfall
---
# TASK-0016 — Implement smart compile-time strategy selection for `||` DAG blocks, `||map`/`||filter`, and `Agent`s (green threads vs OS kernel threads)

## Goal (one sentence)
Implement smart compile-time strategy selection in `compiler.rg` (`StratInlineSequential` green execution vs `StratKernelWorkerJob`/`StratLazyStealableTask` multicore OS kernel threads via `SYS_clone`) for `||` DAG blocks, `||map`/`||filter`, and `Agent`s, and update The Ridgun Book (Chapters 00, 01, 07 across all 7 languages) and `README.md`.

## Plan
- [x] Update `FR-COMP-009` to specify smart compile-time strategy selection between lightweight green-thread execution (`StratInlineSequential`) and multicore OS kernel thread execution (`StratKernelWorkerJob` / `StratLazyStealableTask` via `SYS_clone`).
- [x] Add `"__rg_par_eval__"` to `build_str_pool` and `build_spawn_dispatch_entry` (`NativeFn 2`), and add static heavy-function call-graph classification (`build_heavy_fn_entries`, `attach_heavy_fn_entries`, `env_fn_is_heavy`) in `compiler.rg`.
- [x] Implement smart strategy selection in `compiler.rg` for:
  1. `agent fn` + `send ... to` + `receive from` / `try receive from` (status `1` green-thread agent for lightweight functions vs status `3` multicore batch worker agent using `NCallBuiltin 54` `SYS_clone` for heavy/recursive `fn`).
  2. `||` blocks (`EWhere` and `EParPipe`): execute independent heavy/recursive branches in parallel across OS kernel threads (`SYS_clone` via `"__rg_par_eval__"`), while keeping lightweight branches inline without thread warmup overhead.
  3. `||map` and `||filter`: select fast inline (`NCallBuiltin 53`/`55`) when the static callee is lightweight vs multicore `SYS_clone` (`NCallBuiltin 54`/`56`) when heavy/recursive or dynamic.
- [x] Update The Ridgun Book (Chapters 00, 01, and 07 across `es`, `ca`, `gl`, `eu`, `en`, `pt`, `sv` + regenerate all HTML editions) and `README.md` to showcase the Native Agent Model and Smart Compile-Time Strategy Selection.
- [x] Add automated tests in `src/test/ridgun/test parallel and tensors.rg` verifying multicore `agent fib` batch execution, parallel `||` DAG execution, and green-thread agents, and verify the 2-stage self-hosting fixed point.

## Progress log (append-only, newest last)
- 2026-10-22: Created and started `TASK-0016`.
- 2026-10-22: Updated `FR-COMP-009` (Requirement 6 & AC-5) and implemented smart compile-time strategy selection in `src/main/ridgun/lib/compiler.rg` (`build_heavy_fn_entries`, `"__rg_par_eval__"`, status `3` heavy multicore agents, `select_par_collection_builtin`, `emit_par_where_pair`, and `EParPipe` parallel dispatch).
- 2026-10-22: Added tests for heavy/lightweight `||` pipes, `||map fib`, and `agent fib` in `src/test/ridgun/test parallel and tensors.rg`.
- 2026-10-22: Updated Chapters 00, 01, and 07 in all 7 language editions of The Ridgun Book (`es`, `ca`, `gl`, `eu`, `en`, `pt`, `sv`), regenerated all interactive HTML books via `python3 docs/book/build_book.py`, and updated `README.md`.
- 2026-10-22: Verified 2-stage self-hosting fixed point (`cmp -s target/ridgunc_candidate target/ridgunc_stage3`), promoted `bin/ridgunc` and `bin/stable`, and ran `stable check` and `stable test`.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`
- `src/main/ridgun/lib/compiler.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `README.md`
- `docs/book/es/00-portada-y-prefacio.md`, `docs/book/es/01-introduccion-y-filosofia.md`, `docs/book/es/07-concurrencia-paralelismo-y-tensores.md`, `docs/book/es/index.html`
- `docs/book/ca/00-portada-i-prefaci.md`, `docs/book/ca/01-introduccio-i-filosofia.md`, `docs/book/ca/07-concurrencia-parallelisme-i-tensors.md`, `docs/book/ca/index.html`
- `docs/book/gl/00-portada-e-prefacio.md`, `docs/book/gl/01-introducion-e-filosofia.md`, `docs/book/gl/07-concorrencia-paralelismo-e-tensores.md`, `docs/book/gl/index.html`
- `docs/book/eu/00-azala-eta-hitzaurrea.md`, `docs/book/eu/01-sarrera-eta-filosofia.md`, `docs/book/eu/07-konkurrentzia-paralelismoa-eta-tentsoreak.md`, `docs/book/eu/index.html`
- `docs/book/en/00-cover-and-preface.md`, `docs/book/en/01-introduction-and-philosophy.md`, `docs/book/en/07-concurrency-parallelism-and-tensors.md`, `docs/book/en/index.html`
- `docs/book/pt/00-capa-e-prefacio.md`, `docs/book/pt/01-introducao-e-filosofia.md`, `docs/book/pt/07-concorrencia-paralelismo-e-tensores.md`, `docs/book/pt/index.html`
- `docs/book/sv/00-omslag-och-forord.md`, `docs/book/sv/01-introduktion-och-filosofi.md`, `docs/book/sv/07-konkurrens-parallellism-och-tensorer.md`, `docs/book/sv/index.html`
- `docs/book/index.html`
- `bin/ridgunc`, `bin/stable`

## Verification performed (command → result, newest last)
- `python3 docs/book/build_book.py` → Regenerated all 7 HTML language editions and `docs/book/index.html`.
- `cmp -s target/ridgunc_candidate target/ridgunc_stage3` → 0 (bit-for-bit identical 2-stage self-hosting fixed point).
- `./bin/stable check` → 13 modules checked, 0 errors.
- `./bin/stable test` → 5/5 test suites passed.

## Exact next actions
1. None (task complete; next backlog candidate: persistent `SYS_futex` worker thread pool).

## Decisions / open questions
- Static heavy-function call-graph analysis (`compiler.rg`) selects zero-overhead green-thread inline execution for lightweight functions and multicore `SYS_clone` batch execution (`NCallBuiltin 54`/`56`) for recursive/heavy functions.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
