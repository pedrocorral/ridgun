---
id: TASK-0048
title: Associate agent replies with the requesting thread in ask, send, receive from, and try receive from
status: completed
created: 2026-10-30
completed: 2026-10-30
requirements: [FR-COMP-009]
tests: [TS-COMP-009]
security: []
context_files:
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
scope:
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - bin/ridgunc
owner: agent-001
claimed: 2026-10-30T19:34:59Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only
---
# TASK-0048 — Associate agent replies with the requesting thread in ask, send, receive from, and try receive from

## Goal (one sentence)
Associate agent replies with the requesting thread (`SYS_gettid`) and synchronize channel access so concurrent threads sharing an `Agent` via `ask` or `send` + `receive from` / `try receive from` never mix replies.

## Plan
- [x] Add `@__rg_chan_lock`, blocking `@__rg_builtin_chan_recv`, and `SYS_gettid`-tagged channel/list helpers (`NCallBuiltin 96..99`) in `src/main/ridgun/lib/llvm.rg`.
- [x] Update `send_to`, `receive_from`, `try_receive_from`, and `stop` in `src/main/ridgun/lib/compiler.rg` to tag replies and jobs with the caller's thread ID and match replies by `tid`.
- [x] Rebuild `bin/ridgunc` and verify both `agent_replies_with_ask.rg` and `agent_replies_mixed_send_receive.rg` report `wrong answers: 0`.

## Progress log (append-only, newest last)
- 2026-10-30: Implemented atomic channel synchronization (`@__rg_chan_lock`), blocking `chan_recv` with `SYS_sched_yield`, and `SYS_gettid` reply tagging/matching across `send_to`, `receive_from`, `try_receive_from`, and `stop`; rebuilt `bin/ridgunc` and verified both repros pass with `wrong answers: 0`.

## Files changed (keep current)
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/lib/compiler.rg`
- `bin/ridgunc`

## Verification performed (command → result, newest last)
- `./bin/ridgunc run /tmp/ridgun-compiler/2026-10-30/repros/agent_replies_with_ask.rg` → `wrong answers: 0`
- `./bin/ridgunc run /tmp/ridgun-compiler/2026-10-30/repros/agent_replies_mixed_send_receive.rg` → `wrong answers: 0`

## Exact next actions
1. None (completed).

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
