---
updated: 2026-10-22T21:03
active_task: none
agent_runtime: gemini
---
# Session state — read this first when resuming

## Where we are (3 lines max)
- Branch `main`: Completed `TASK-0016` (`FR-COMP-001`, `FR-COMP-009`, `TS-FUNC-001`): smart compile-time strategy selection in `compiler.rg` (green-thread inline execution for lightweight functions vs multicore OS kernel threads via `SYS_clone` for heavy/recursive `||` blocks, `||map`/`||filter`, and `agent`s), plus updates to The Ridgun Book (Chapters 00, 01, 07 in all 7 language editions + HTML) and `README.md`.
- 2-stage self-hosting fixed point (`ridgunc_candidate == ridgunc_stage3`), `./bin/stable check` (13 modules), `./bin/stable test` (5/5 suites), and `aix docs validate` are all green.
## Files to load for the active task (nothing else)
- `docs/road-map/INDEX.md`
## Last verified facts (tests green? migrations applied? env?)
- `./bin/stable check` = 13 modules checked, 0 errors (`v0.9.12`).
- `./bin/stable test` = 5/5 test suites passed (`test basics.rg`, `test core language.rg`, `test lib and plugins.rg`, `test parallel and tensors.rg`, `test strings.rg`).
- `aix docs validate` = 0 errors.
## Immediate next action
- Pick next roadmap task (e.g., persistent pre-warmed `SYS_futex` worker thread pool in `x86_64.rg`).
## Blockers / questions for the user
- None.
