---
id: TASK-0038
title: Fix sequence mask length and type checking, ErrUseAfterSend on pipelines, automatic => () discard, and ask to skill docs
status: completed
created: 2026-10-27
completed: 2026-10-27
requirements: [FR-COMP-008, FR-COMP-009, FR-COMP-014]
tests: []
security: []
context_files:
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/compiler.rg
  - .aix/custom/instructions/languages/ridgun.md
  - .aix/custom/skills/implement/code-ridgun/SKILL.md
  - tests/run.rg
scope:
  - src/main/ridgun/**
  - src/test/ridgun/**
  - tests/**
  - docs/**
  - .aix/custom/**
owner: agent-001
claimed: 2026-10-27T18:10:49Z
claimed_by: agent gemini@solarfall
---
# TASK-0038 — Fix sequence mask length and type checking, ErrUseAfterSend on pipelines, automatic => () discard, and ask to skill docs

## Goal (one sentence)
Enforce sequence mask `(+ _ ... +)` length and element type checking against tuples, fix `ErrUseAfterSend` detection across pipelines and all tensor/mutable variables, automatically discard the final expression value when a function returns `=> ()`, and document `-> ask to ag` in Ridgun instructions and skills.

## Plan
- [x] Update `typecheck.rg` so `ESeqSelect base mask` verifies that `mask` position count matches the tuple length of `base` (`TyTuple elem_tys`) and computes the exact selected element type(s) (`TyUnit`, `T`, or `TyTuple [...]`) instead of `TyVar "_seq"` / hardcoded `TyInt`.
- [x] Update `analyzer.rg` so `ErrUseAfterSend` triggers on `send v to ag` and `v -> send to ag` (including `Tensor[...]` allocations and pipeline-bound variables).
- [x] Update `typecheck.rg` (`check case body ty` and `check guard body ty`) and `compiler.rg` (`lower tail return` / `lower final block expr`) so a function declared `=> ()` automatically discards a non-`()` final expression value and returns `()`.
- [x] Update `.aix/custom/instructions/languages/ridgun.md` and `.aix/custom/skills/implement/code-ridgun/SKILL.md` (and `aix install`) to document `-> ask to ag` and automatic `=> ()` final value discarding.
- [x] Add acceptance tests in `tests/cases/` covering sequence mask length mismatch, sequence mask element type mismatch, `v -> send to ag` `ErrUseAfterSend`, and automatic `=> ()` return discarding, then bootstrap `ridgunc` and `stable` v0.9.24.

## Progress log (append-only, newest last)
- 2026-10-27: Created and claimed `TASK-0038`.
- 2026-10-27: Implemented sequence mask length and element type checking in `typecheck.rg`, automatic `=> ()` final value discarding in `typecheck.rg` and `compiler.rg`, `ErrUseAfterSend` on pipelines (`v -> send to ag`) and all sent variables in `analyzer.rg`, updated `.aix/custom/` instructions and skills (`-> ask to ag` and automatic `=> ()` discarding), added 6 regression tests in `tests/cases/`, and bootstrapped `ridgunc` and `stable` v0.9.24 (`6/6` `stable test` suites and `52/52` `tests/run.rg` checks green).

## Files changed (keep current)
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `tests/cases/tuples/mask_length_short_fails.rg`
- `tests/cases/tuples/mask_length_long_fails.rg`
- `tests/cases/tuples/mask_out_of_range_fails.rg`
- `tests/cases/tuples/mask_type_mismatch_fails.rg`
- `tests/cases/agents/use_after_pipe_send_fails.rg`
- `tests/cases/functions/auto_unit_return_discard.rg`
- `.aix/custom/instructions/languages/ridgun.md`
- `.aix/custom/skills/implement/code-ridgun/SKILL.md`
- `docs/requirements/functional/compiler/FR-COMP-014-idiomatic-pipeline-chaining-and-side-effect-statements.md`
- `docs/road-map/going-on/TASK-0038-fix-sequence-mask-length-and-type-checking-errusea.md`

## Verification performed (command → result, newest last)
- `./bin/stable check` → `Checked 14 module(s) — 0 errors.`
- `./bin/stable test` → `Passed 6/6 test suite(s) — 0 failures.`
- `./bin/ridgunc run tests/run.rg` → `52 of 52 promised behaviours passed`

## Exact next actions
1. None (task complete).

## Decisions / open questions
- User confirmed automatic discarding of the final expression value when a function signature is `=> ()`.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
