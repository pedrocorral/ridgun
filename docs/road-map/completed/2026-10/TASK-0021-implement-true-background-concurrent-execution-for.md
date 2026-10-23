---
id: TASK-0021
title: Implement true background concurrent execution for stateful Agents
status: completed
created: 2026-10-23
completed: 2026-10-23
requirements:
  - FR-COMP-009
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/parser.rg
  - src/test/ridgun/test parallel and tensors.rg
scope:
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/parser.rg
  - src/test/ridgun/test parallel and tensors.rg
  - src/test/ridgun/test lib and plugins.rg
  - build.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
owner: agent-001
claimed: 2026-10-23T09:07:50Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0021 — Implement true background concurrent execution for stateful Agents

## Goal (one sentence)
Make stateful agents (`agent fn init_state`, both `S M => S` and `S M => S R`) execute their message handlers asynchronously in the background via `b_id 57` (`async_spawn`), `b_id 58` (`async_poll`), and `b_id 59` (`async_await`) so `send msg to ag` returns immediately (~0 ms) while preserving sequential state transitions `S -> S'` and FIFO response ordering.

## Plan
- [x] Update `lower_agent_call` in `src/main/ridgun/lib/compiler.rg` so stateful agents (`status == 2`) store `(2, (cur_state, opt_job_id))` in `ch_state`, spawn jobs in the background on `send_to` via `b_id 57`, and poll/await + update state on `try_receive_from`, `receive_from`, and `stop`.
- [x] Update `build_spawn_dispatch_instrs` in `src/main/ridgun/lib/compiler.rg` so `arity == 3` supports both 3-tuple `(a, b, c)` and stateful 2-tuple `(state, (m1, m2))`.
- [x] Add `strip_rgc_magic` in `src/main/ridgun/lib/parser.rg` when concatenating `.rglib` bundles.
- [x] Add stateful sleeping agent concurrency & timing tests (`dormir con estado`) to `src/test/ridgun/test parallel and tensors.rg`.
- [x] Verify 2-stage self-hosting fixed point (`ridgunc` v0.9.15), rebuild `stable`, run `./bin/stable test` and `aix docs validate`, and commit.

## Progress log (append-only, newest last)
- 2026-10-23: Updated `lower_agent_call` (`agent`, `send_to`, `receive_from`, `try_receive_from`, `stop`) and `build_spawn_dispatch_instrs` in `src/main/ridgun/lib/compiler.rg`, added `strip_rgc_magic` in `src/main/ridgun/lib/parser.rg`, added `dormir con estado` timing test in `src/test/ridgun/test parallel and tensors.rg`, verified 2-stage fixed point (`ridgunc_stage2 == ridgunc_stage3`, `9c89f3d132e263e348cc39bb474fb3a03268a13ba692ef4ce49d20333fc9ffe5`), rebuilt `stable` v0.9.15, and passed 5/5 test suites and `aix docs validate`.

## Files changed (keep current)
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`

## Verification performed (command → result, newest last)
- `sha256sum target/ridgunc_stage2 target/ridgunc_stage3` → `9c89f3d132e263e348cc39bb474fb3a03268a13ba692ef4ce49d20333fc9ffe5` (exact byte-for-byte fixed point)
- `./bin/stable check` → 13 modules checked, 0 errors (`v0.9.15`)
- `./bin/stable test` → 5/5 test suites passed, 0 failures
- `aix docs validate` → 0 errors

## Exact next actions
1. Complete task and commit.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
