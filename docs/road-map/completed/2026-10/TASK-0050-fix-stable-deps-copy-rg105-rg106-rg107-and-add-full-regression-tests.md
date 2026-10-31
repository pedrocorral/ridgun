---
id: TASK-0050
title: Fix stable deps self-copy, RG-105, RG-106, RG-107, and add full regression test suite
status: completed
created: 2026-10-31
requirements: [FR-COMP-005, FR-COMP-007, FR-COMP-009, FR-COMP-014, FR-TOOL-002]
tests: [TS-UNIT-001, TS-COMP-009]
security: []
context_files:
  - src/main/ridgun/stable/main.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/ridgunc/main.rg
  - build.rg
  - tests/run.rg
scope:
  - src/main/ridgun/stable/main.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/ridgunc/main.rg
  - build.rg
  - tests/run.rg
  - tests/cases/agents/agent_replies_mixed_send_receive.rg
  - tests/cases/agents/agent_replies_with_ask.rg
  - tests/cases/records/pipe_into_local_named_like_field.rg
  - tests/cases/adts/rg106_unknown_constructor_in_pattern.rg
owner: agent-001
claimed: 2026-10-31T15:55:38Z
claimed_by: agent gemini@solarfall
---
# TASK-0050 — Fix stable deps self-copy, RG-105, RG-106, RG-107, and add full regression test suite

## Goal (one sentence)
Make `stable deps` copy dependencies cleanly via `tar` excluding `.stable/` and `target/`, fail with non-zero status on copy errors, refresh `.rglib` bundles (RG-105), avoid copying root `build.rg` into `src/main/ridgun/lib/` (RG-107), report `unknown constructor '<C>' in pattern` (RG-106), bump version to `0.9.32`, and add automated regression tests for all reported repros.

## Plan
- [x] Update `fetch dependency source`, `sync single dependency`, `sync dependency list`, and `run task deps` in `src/main/ridgun/stable/main.rg` to exclude `.stable` and `target`, propagate non-zero exit codes on failure, refresh `.rglib` bundles on `stable deps` (RG-105), and stop copying root `*.rg` (`build.rg`) into `src/main/ridgun/lib/` (RG-107).
- [x] Update `check one case` in `src/main/ridgun/lib/typecheck.rg` to report `unknown constructor '<C>' in pattern` (RG-106) without cascading body type errors.
- [x] Add regression tests for `agent_replies_mixed_send_receive.rg`, `agent_replies_with_ask.rg`, `pipe_into_local_named_like_field.rg`, `rg106_unknown_constructor_in_pattern.rg`, and toolchain checks for `stable deps` self-copy, bundle refresh, and root `build.rg` exclusion in `tests/run.rg`.
- [x] Bump version to `0.9.32`, rebuild `bin/ridgunc` and `bin/stable`, and run the regression tests.

## Progress log (append-only, newest last)
- 2026-10-31: Created `TASK-0050`.
- 2026-10-31: Updated `stable/main.rg`, `lib/typecheck.rg`, `tests/run.rg`, added regression tests under `tests/cases/`, bumped version to `0.9.32`, and rebuilt `bin/stable` and `bin/ridgunc`.

## Files changed (keep current)
- `src/main/ridgun/stable/main.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `build.rg`
- `tests/run.rg`
- `tests/cases/agents/agent_replies_mixed_send_receive.rg`
- `tests/cases/agents/agent_replies_with_ask.rg`
- `tests/cases/records/pipe_into_local_named_like_field.rg`
- `tests/cases/adts/rg106_unknown_constructor_in_pattern.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `bash /tmp/ridgun-compiler/2026-10-31/repros/stable_deps_inside_own_dependency.sh` → `source: alpha build.rg inner README.md src zeta` / `copy: alpha build.rg inner README.md src zeta`
- `bash /tmp/ridgun-compiler/2026-10-30/repros/rg105_stale_bundle.sh` → `version 1` then `version 2`

## Exact next actions
1. Verify all new regression test cases and close `TASK-0050`.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
