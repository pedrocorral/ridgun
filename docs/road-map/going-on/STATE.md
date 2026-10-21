---
updated: 2026-10-21T13:44
active_task: none
agent_runtime: gemini
---
# Session state — read this first when resuming

## Where we are (3 lines max)
- Branch `main`: Completed `TASK-0008` (`FR-COMP-005` AC-4) — bare type-name variants in `type` and `expand type` (`type Something = String | Int | MyStruct Float Int`, `expand type Something = Bool`) without redundant `Int Int` / `String String` constructor names.
- Callers can pass bare values (`describe "hej"`, `describe 42`, `describe True`) or explicit type-constructors (`describe (String "explicit")`, `describe (Int 99)`), and equations match both literals (`"admin"`, `0`) and typed patterns (`(String s)`, `(Int n)`, `(Bool b)`).
- Bootstrapped Stage 1 & Stage 2 `target/ridgunc` and `target/stable` and verified 13/13 modules and 4/4 test suites pass.
## Files to load for the active task (nothing else)
- `docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/test/ridgun/test_core_language.rg`
## Last verified facts (tests green? migrations applied? env?)
- `./target/stable check` = 13 modules checked, 0 errors.
- `./target/stable test` = 4/4 test suites passed (`test_basics.rg`, `test_core_language.rg`, `test_parallel_and_tensors.rg`, `test_strings.rg`).
- `aix docs validate` = 0 errors.
## Immediate next action
- Ready for next user request.
## Blockers / questions for the user
- None.
