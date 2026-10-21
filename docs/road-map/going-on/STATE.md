---
updated: 2026-10-21T19:58
active_task: TASK-0012
agent_runtime: gemini
---
# Session state — read this first when resuming

## Where we are (3 lines max)
- Branch `main`: Completed and committed `TASK-0010` (`FR-COMP-006`) and `TASK-0011` (`FR-TOOL-003`) in `7f1b977`, and wrote `/tmp/ridgun_posix_io_library_spec.md` for the libraries team (`posix.rglib` and `io.rglib`).
- Specified and documented `FR-COMP-007` (Low-level Linux FD/poll/syscall primitives `sys open`, `sys close`, `sys read fd`, `sys write fd`, `sys poll`, `sys kill`, `sys call`, `sys deadline ms`, `sys remaining ms` + duration literals `_ms`, `_s`, `_min` + declarative `with timeout <duration> do` blocks) in `docs/requirements/functional/compiler/FR-COMP-007-low-level-posix-fd-poll-syscalls-and-with-timeout-blocks.md` and `docs/lang/spec.md`.
- Started `TASK-0012` in `docs/road-map/going-on/TASK-0012-implement-low-level-linux-fd-poll-syscall-primitiv.md`.
## Files to load for the active task (nothing else)
- `docs/requirements/functional/compiler/FR-COMP-007-low-level-posix-fd-poll-syscalls-and-with-timeout-blocks.md`
- `docs/road-map/going-on/TASK-0012-implement-low-level-linux-fd-poll-syscall-primitiv.md`
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/arm64.rg`
## Last verified facts (tests green? migrations applied? env?)
- `./bin/stable check` = 13 modules checked, 0 errors.
- `./bin/stable test` = 5/5 test suites passed (`test basics.rg`, `test core language.rg`, `test lib and plugins.rg`, `test parallel and tensors.rg`, `test strings.rg`).
- `aix docs validate` = 0 errors.
## Immediate next action
- Implement `FR-COMP-007` (`TASK-0012`) across `lexer.rg`, `parser.rg`, `typecheck.rg`, `compiler.rg`, `x86_64.rg`, `arm64.rg`, `formatter.rg`, and `vm.rg`.
## Blockers / questions for the user
- None.
