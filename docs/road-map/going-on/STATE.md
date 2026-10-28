---
updated: 2026-10-28T10:51
active_task: none
agent_runtime: antigravity
---
# Session state — read this first when resuming

## Where we are (3 lines max)
- Completed `TASK-0042`: documented `OPT-013` (Direct SSA Register Calling Convention `@__rg_fn_{fid}_reg`), `OPT-014` (direct-call `map`/`filter`/`fold` specialization), and the `RMM1`/`RMM2` evolution guide in `docs/etc/compiler_optimizations.md` and `FR-COMP-011`, and implemented them in `llvm.rg` and `compiler.rg` (`v0.9.28`).

## Files to load for the active task (nothing else)
- None (no active task).

## Last verified facts (tests green? migrations applied? env?)
- `bin/ridgunc` and `bin/stable` (`v0.9.28`) bootstrapped (Stage 1 + Stage 2) and installed; `stable check` passes 14/14 modules, `stable test` passes 6/6 suites, and `tests/run.rg` passes 56/56 promised behaviours.

## Immediate next action
- Await next user task.

## Blockers / questions for the user
- None.
