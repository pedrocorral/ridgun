---
id: TASK-0067
title: Solstice report lista-cuadratica: list append through a borrowing callee in a tail call is quadratic
status: completed
created: 2026-11-10
completed: 2026-11-10
requirements: [FR-COMP-011]
tests: [TS-COMP-011]
security: []
context_files: [docs/etc/compiler_optimizations.md, src/main/ridgun/lib/compiler.rg]
scope: [src/main/ridgun/lib/compiler.rg, tests/cases/perf/, docs/etc/compiler_optimizations.md]
owner: agent-001
claimed: 2026-11-10T08:40:24Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0067 — Solstice report lista-cuadratica: list append through a borrowing callee in a tail call is quadratic

## Goal (one sentence)
A loop that appends to its list through a callee that borrows a tuple parameter (`scan n (first step) (emit step acc)`, `emit (_, h) acc = acc :: [h]`) runs in linear time again, as before OPT-018.

## Plan
- [x] Reproduce `/tmp/ridgun-compiler/2026-11-10/lista-cuadratica/` on 0.9.50: 8 000 rounds 853 ms on both backends.
- [x] Move owned arguments into borrowing callees inside tail-call arguments (`lower tco borrow call`).
- [x] Perf case, OPT-018 doc, bootstrap, checks, install 0.9.51 (with TASK-0066); answer Solstice.

## Progress log (append-only, newest last)
- 2026-11-10: Cause: `lower tco arg expr` moves a local on its last use only into a "direct call target", and that excluded every callee with a borrow mask (OPT-018, 0.9.46). `emit` borrows its tuple, so `acc` was cloned and `acc :: [h]` copied the whole list each round. Fix: `is plain call target` holds the shared conditions; `is borrow call target` sends such calls to `lower tco borrow call`, which lowers owned arguments with `lower tco arg expr` (moves) and borrowed ones as `lower borrow call` does. Locals passed to borrowed parameters are read after the owned arguments, so they are added to the later uses and never moved. The call is inside the arguments of a tail call, never in tail position itself (OPT-018 excludes callees called in tail position), so the tail-call rule holds.
- 2026-11-10: Seen in passing: building a string with `acc + x` in a self tail call is quadratic (100 000 rounds: 2.3 s). Not part of this report; the case does not use it.

## Files changed (keep current)
- `src/main/ridgun/lib/compiler.rg`: `is plain call target`, `is borrow call target`, `lower tco borrow call`, `borrow peeked args`, `lower tco borrow args`.
- `tests/cases/perf/append_through_borrowing_callee.rg`.
- `docs/etc/compiler_optimizations.md` (OPT-018: tail-call arguments, incident).

## Verification performed (command → result, newest last)
All runs capped (`ulimit -v` 4 GB, timeout).
- Stage 1, both backends: the report's `lista.rg` 2 000 / 8 000 / 100 000 rounds in 2 / 9 / 112 ms (LLVM), 3 / 11 / 124 ms (x86-64); `sin-tupla.rg` unchanged (linear).
- New case: passes on both backends in 0.3–0.4 s; with 0.9.50 it passes 10 s.
- Bootstrap s1 → s4 (0.9.51, with TASK-0066 and TASK-0067): s3 and s4 differ in 2 bytes (temporary file name), fixed point.
- `tests/run.rg functions/ perf/ names/ lists/ tensors/` with s3 and its `stable`: 136 of 136 after the new case's strict signatures were fixed (llvm 68, x86-64 68).
- Toolchain checks tc8 (lib field accessor) and tc9 (this report) run by hand with s3: `1 []` and `True k:a`.
- Not run, to save CPU at the user's request: the other case groups, `src/test/ridgun` unit tests, libs `stable test`.
- Installed: s3 and its `stable` in `target/*_candidate` and `bin/`.

## Exact next actions
1. None: done; Solstice answered in the shared compiler notes. String `+` follow-up: TASK-0068.

## Decisions / open questions
- Quadratic `acc + x` string building in tail calls: separate follow-up.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (none)  - [x] docs INDEX updated (no new docs)  - [x] coverage matrix regenerated (not kept in this project)
