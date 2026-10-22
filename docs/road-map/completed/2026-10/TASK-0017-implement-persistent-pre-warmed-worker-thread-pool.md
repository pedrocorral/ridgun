---
id: TASK-0017
title: Implement persistent pre-warmed worker thread pool in Ridgun runtime
status: completed
created: 2026-10-22
completed: 2026-10-22
requirements:
  - FR-COMP-001
  - FR-COMP-009
tests:
  - TS-FUNC-001
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/x86_64.rg
  - src/test/ridgun/test parallel and tensors.rg
  - build.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
scope:
  - src/main/ridgun/lib/x86_64.rg
  - src/test/ridgun/test parallel and tensors.rg
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - build.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
owner: agent-001
claimed: 2026-10-22T19:38:35Z
claimed_by: agent gemini@solarfall
---
# TASK-0017 — Implement persistent pre-warmed worker thread pool in Ridgun runtime

## Goal (one sentence)
Keep the 8 worker threads in `src/main/ridgun/lib/x86_64.rg` alive across parallel batches so worker stacks and threads are created once on first heavy batch and reused on subsequent batches without repeated thread setup/teardown.

## Plan
- [x] Add `x86 rt par pool ext` in `src/main/ridgun/lib/x86_64.rg` and connect `x86 rt p4 par worker pool` so worker threads park and wake across batches.
- [x] Update `FR-COMP-009` to document the persistent pre-warmed worker thread pool.
- [x] Bump version `0.9.12` -> `0.9.13` in `build.rg`, `src/main/ridgun/ridgunc/main.rg`, and `src/main/ridgun/stable/main.rg`.
- [x] Verify 2-stage self-hosting fixed point (`ridgunc_candidate == ridgunc_stage3`), promote `bin/ridgunc` and `bin/stable`, and run `./bin/stable check` and `./bin/stable test`.

## Progress log (append-only, newest last)
- 2026-10-22: Created and started `TASK-0017`.
- 2026-10-22: Implemented `x86 rt par pool ext` in `src/main/ridgun/lib/x86_64.rg`, updated `FR-COMP-009`, bumped version to `0.9.13`, added multi-batch persistent worker pool assertions in `src/test/ridgun/test parallel and tensors.rg`, and verified 2-stage self-hosting fixed point + 5/5 test suites green.

## Files changed (keep current)
- `src/main/ridgun/lib/x86_64.rg`
- `docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `bin/ridgunc`, `bin/stable`
- `.aix/custom/skills/core/lessons-learnt-notes/lessons/git-commit-identity.md`
- `.aix/custom/skills/core/lessons-learnt-notes/lessons/no-elf-cave-scanning-or-binary-patching.md`
- `.aix/custom/skills/core/lessons-learnt-notes/SKILL.md`
- `.agents/skills/core-lessons-learnt-notes/lessons/git-commit-identity.md`
- `.agents/skills/core-lessons-learnt-notes/lessons/no-elf-cave-scanning-or-binary-patching.md`
- `.agents/skills/core-lessons-learnt-notes/SKILL.md`

## Verification performed (command → result, newest last)
- `cmp -s target/ridgunc_candidate target/ridgunc_stage3` → 0 (bit-for-bit identical 2-stage self-hosting fixed point).
- `./bin/stable check` → Checked 13 module(s) — 0 errors (`v0.9.13`).
- `./bin/stable test` → Passed 5/5 test suite(s) — 0 failures.
- `.aix/bin/aix docs validate` → 0 errors.

## Exact next actions
1. None (task complete).

## Decisions / open questions
- Emit `x86 rt par pool ext` cleanly through `x86 build rt phase4 bytes` in `src/main/ridgun/lib/x86_64.rg` and rebuild from source.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
