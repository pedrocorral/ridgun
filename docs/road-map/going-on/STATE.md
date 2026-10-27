---
updated: 2026-10-27T18:58
active_task: none
agent_runtime: antigravity
---
# Session state — read this first when resuming

## Where we are (3 lines max)
- Completed `TASK-0037`: enforced `" "` != `"_"` in Ridgun function names (`fn :: a b` vs `fn :: a_b`), enforced `--strict` rejection of `_` in function/built-in calls while allowing `_` in variables and record fields, migrated all codebase calls to space-separated names without `_ = expr` statements, and bootstrapped `ridgunc` & `stable` v0.9.23.

## Files to load for the active task (nothing else)
- None (no active task).

## Last verified facts (tests green? migrations applied? env?)
- `bin/ridgunc` and `bin/stable` (v0.9.23) installed; `stable check` passes 14/14 modules, `stable test` passes 6/6 suites, and `tests/run.rg` passes 46/46 promised behaviours.

## Immediate next action
- Pick or create the next road-map task when requested by the user.

## Blockers / questions for the user
- None.
