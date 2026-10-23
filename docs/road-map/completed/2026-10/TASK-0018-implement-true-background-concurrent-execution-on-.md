---
id: TASK-0018
title: Implement true background concurrent execution on send, receive from, and try receive from for Agents
status: completed
created: 2026-10-22
completed: 2026-10-23
requirements: [FR-COMP-007, FR-COMP-009]
tests: [TS-COMP-005]
security: []
context_files:
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test parallel and tensors.rg
scope:
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/compiler.rg
  - src/test/ridgun/test parallel and tensors.rg
  - build.rg
  - src/main/ridgun/ridgunc.rg
  - src/main/ridgun/stable.rg
owner: agent-001
claimed: 2026-10-22T20:30:06Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0018 — Implement true background concurrent execution on send, receive from, and try receive from for Agents

## Goal (one sentence)
Dispatch `Agent` messages immediately to background worker threads at `send` time so `send` returns in ~0 ms without blocking the sender, background work progresses concurrently with the caller, `receive from` awaits completion via futex, and `try receive from` polls non-blockingly (`None` while running, `Some` when ready).

## Plan
- [x] Design `b_id 57` (`async_spawn`), `b_id 58` (`async_poll`), and `b_id 59` (`async_await`) in `x86 rt par pool ext` (`src/main/ridgun/lib/x86_64.rg`)
- [x] Implement `b_id 57`, `58`, `59` in `src/main/ridgun/lib/x86_64.rg` and wire jump table entries 57..59
- [x] Update `lower_agent_call` in `src/main/ridgun/lib/compiler.rg` and add Akka-style synchronous `ask` (`ask ag msg` and `ask msg to ag`) across `parser.rg`, `analyzer.rg`, `typecheck.rg`, and `compiler.rg`
- [x] Add timing and non-blocking `try receive from` + `ask` regression tests in `src/test/ridgun/test parallel and tensors.rg`
- [x] Verify 2-stage self-hosting fixed point (`0.9.14`) and run full test suite
## Progress log (append-only, newest last)
- 2026-10-23: Implemented `b_id 57` (`async_spawn`), `b_id 58` (`async_poll`), and `b_id 59` (`async_await`) in `x86 rt par pool ext` (`src/main/ridgun/lib/x86_64.rg`), added synchronous `ask` (`ask ag msg` / `ask msg to ag`) across the compiler pipeline, verified true concurrent background execution for sleeping (`dormir agente`) and heavy CPU (`fib`) agents, verified 2-stage self-hosting fixed point (`0.9.14`, SHA-256 `ce485428cd812487a20ccd92c3f555303e46a5e81038f2d43489c53ecad7e399`), and passed all 5 test suites.
## Files changed (keep current)
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`
## Verification performed (command → result, newest last)
- `./bin/stable check` → 13 modules checked, 0 errors (`v0.9.14`).
- `./bin/stable test` → 5/5 test suites passed.
- `aix docs validate` → 0 errors.
## Exact next actions
1. Completed.
## Decisions / open questions
- None.
## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
