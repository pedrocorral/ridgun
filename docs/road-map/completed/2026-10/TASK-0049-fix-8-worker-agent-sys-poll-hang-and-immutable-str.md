---
id: TASK-0049
title: Fix 8-worker agent sys_poll hang and immutable String multi-send
status: completed
created: 2026-10-30
completed: 2026-10-31
requirements: [FR-COMP-002, FR-COMP-009, FR-COMP-014]
tests: [TS-UNIT-001, TS-COMP-009]
security: []
context_files:
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
  - build.rg
  - tests/run.rg
  - tests/cases/agents/use_after_pipe_send_fails.rg
  - tests/cases/agents/hang_agents_sys_poll.rg
  - tests/cases/agents/rg108_send_same_string_twice.rg
scope:
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
  - build.rg
  - tests/run.rg
  - tests/cases/agents/use_after_pipe_send_fails.rg
  - tests/cases/agents/hang_agents_sys_poll.rg
  - tests/cases/agents/rg108_send_same_string_twice.rg
owner: agent-001
claimed: 2026-10-30T21:54:57Z
claimed_by: agent gemini@solarfall
---
# TASK-0049 — Fix 8-worker agent sys_poll hang and immutable String multi-send

## Goal (one sentence)
Eliminate the 8-worker pool deadlock when worker agents spawn/await inner heavy agents (`sys_poll`), and allow immutable bindings (`String`, `Int`, etc.) to be sent to multiple agents without false-positive `UseAfterChannelSendError`.

## Plan
- [x] Update `mark sent expr vars` in `src/main/ridgun/lib/analyzer.rg` so only `mut` / `Tensor` variables (`mut_vars`) are marked as moved on channel/agent send.
- [x] Add `@__rg_builtin_job_spawn` (`57`), `@__rg_builtin_job_poll` (`58`), and `@__rg_builtin_job_await` (`59`) in `src/main/ridgun/lib/llvm.rg` so nested jobs spawned from worker threads (`SYS_gettid != SYS_getpid`) execute directly on the worker thread without exhausting the 8-worker pool, and pool-full spawns sleep (`SYS_nanosleep`) instead of spinning.
- [x] Rebuild `bin/ridgunc` and `target/ridgunc` and verify both repros (`rg108_send_same_string_twice.rg` and `hang_agents_sys_poll.rg` for `N = 4, 7, 8, 9, 16`).

## Progress log (append-only, newest last)
- 2026-10-30: Created and started `TASK-0049`; updated `analyzer.rg`, `llvm.rg`, and `tests/cases/agents/use_after_pipe_send_fails.rg`.

## Files changed (keep current)
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `build.rg`
- `tests/run.rg`
- `tests/cases/agents/use_after_pipe_send_fails.rg`
- `tests/cases/agents/hang_agents_sys_poll.rg`
- `tests/cases/agents/rg108_send_same_string_twice.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/ridgunc build /tmp/ridgun-compiler/2026-10-30/repros/rg108_send_same_string_twice.rg -o /tmp/test_rg108 && /tmp/test_rg108` → `2`
- `./bin/ridgunc build /tmp/ridgun-compiler/2026-10-30/repros/hang_agents_sys_poll.rg -o /tmp/test_hang_poll && /tmp/test_hang_poll 4 7 8 9 16` → `wrong=0`

## Exact next actions
1. Verify build and repro outputs and close `TASK-0049`.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
