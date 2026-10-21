---
updated: 2026-10-21T14:25
active_task: none
agent_runtime: gemini
---
# Session state — read this first when resuming

## Where we are (3 lines max)
- Branch `main`: Completed `TASK-0009` (`FR-COMP-005` AC-5) — natural-language spaces (`" "`) instead of underscores (`_`) in `fn ::` declarations and calls, built-in/test calls (`assert equals`, `str len`, `read file`, `cmm same ptr`), higher-order function arguments (`map double val xs`), `build.rg`, and `.rg` filenames (`test basics.rg`, `test core language.rg`, `test parallel and tensors.rg`, `test strings.rg`).
- Updated `harness/` (synced to `.aix/` and `.agents/`), `README.md`, `docs/lang/spec.md`, and Chapters 02 and 06 across all 7 languages of the Ridgun book (`sv`, `es`, `en`, `pt`, `ca`, `gl`, `eu`).
- Bootstrapped Stage 1 & Stage 2 `target/ridgunc` and `target/stable` and verified 13/13 modules and 4/4 space-named test suites pass.
## Files to load for the active task (nothing else)
- `docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test core language.rg`
## Last verified facts (tests green? migrations applied? env?)
- `./target/stable check` = 13 modules checked, 0 errors.
- `./target/stable test` = 4/4 test suites passed (`test basics.rg`, `test core language.rg`, `test parallel and tensors.rg`, `test strings.rg`).
- `aix docs validate` = 0 errors.
## Immediate next action
- Ready for next user request.
## Blockers / questions for the user
- None.
