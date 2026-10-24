---
updated: 2026-10-24T15:01
active_task: none
agent_runtime: gemini
---
# Session state — read this first when resuming

## Where we are (3 lines max)
- Branch `main`: Working on `TASK-0023` (removing `global ::`, `context ::`, `shared ::`, `atomic`, and user `with <ctx> = <val> do` across the compiler, tests, and books).
## Files to load for the active task (nothing else)
- `docs/road-map/going-on/TASK-0023-remove-global-context-shared-and-atomic-from-ridgu.md`
- `docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`
- `src/main/ridgun/lib/ast.rg`
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/formatter.rg`
- `src/test/ridgun/test parallel and tensors.rg`
## Last verified facts (tests green? migrations applied? env?)
- Committed `37c1bd5` (`v0.9.17`).
## Immediate next action
- Remove `global ::`, `context ::`, `shared ::`, and `atomic` from `src/main/ridgun/lib/*.rg`, tests, and books, and verify `v0.9.18`.
## Blockers / questions for the user
- None.
