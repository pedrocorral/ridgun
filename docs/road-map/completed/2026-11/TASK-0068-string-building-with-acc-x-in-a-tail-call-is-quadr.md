---
id: TASK-0068
title: String building with acc + x in a tail call is quadratic
status: completed
created: 2026-11-10
completed: 2026-11-10
requirements: [FR-COMP-011]
tests: [TS-COMP-011]
security: []
context_files: [docs/etc/compiler_optimizations.md, src/main/ridgun/lib/compiler.rg]
scope: [src/main/ridgun/lib/compiler.rg, tests/cases/perf/, docs/etc/compiler_optimizations.md]
owner: agent-001
claimed: 2026-11-10T09:35:25Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0068 — String building with acc + x in a tail call is quadratic

## Goal (one sentence)
`rep x n acc = rep x (n - 1) (acc + x)` appends in place and runs in linear time on both backends.

## Plan
- [x] Find why `acc + x` copies `acc`: `lower tco arg expr` cloned the left operand of `+`, and the runtime's `+` always builds a new String of the exact size (no in-place path for Strings, unlike `::` on lists).
- [x] Type checker fact `fn|$v|S` for `v + r` on Strings; tail-position lowering moves `v` and calls runtime extension builtin 121 (in-place append with a doubling buffer, fallback to the usual `+`).
- [x] Perf case (speed, sharing, chains, memory), OPT-020 and runtime_ext docs; bootstrap, affected checks, install 0.9.52.

## Progress log (append-only, newest last)
- 2026-11-10: Found while fixing TASK-0067: 100 000 rounds of `rep "a" n ""` take 2.3 s with 0.9.51 stage 1 (quadratic). The user asked to fix it after TASK-0066/0067.
- 2026-11-10: Moving `acc` alone changed nothing (2.16 s): the runtime's String `+` always allocates. A String value points to a header `{capacity, data, length, rc}` (the layout `rt_box_rc_vec` builds; the list `::` path checks rc at +24); a clone adds one to rc. So "one owner" is rc 1, and the append can live in the C runtime extension without touching the hand-made kernel. The old buffer is freed by dropping a String built around it, so the allocator stays the runtime's.
- 2026-11-10: Only variables that are the left operand of a String `+` get a fact, so other code and compile time are unaffected; builtin 121 checks the tags again at run time, so a wrong fact can only cost the fallback. Chains `acc + sep + x` (parsed `(acc + sep) + x`) are handled through `str add chain`.

## Files changed (keep current)
- `src/main/ridgun/lib/typecheck.rg`: `str add fact`, `EBin OpAdd (EVar v) r` clause.
- `src/main/ridgun/lib/compiler.rg`: `EBin OpAdd` clause of `lower tco arg expr`, `str add chain`.
- `src/main/ridgun/lib/x86_64.rg`: runtime extension bytes (11 504).
- `docs/etc/runtime_ext.md` (id 121, size, C source), `docs/etc/compiler_optimizations.md` (OPT-020).
- `tests/cases/perf/string_append_in_tail_call.rg`.
- Version 0.9.52: `build.rg`, `ridgunc/main.rg`, `stable/main.rg`.

## Verification performed (command → result, newest last)
All runs capped (`ulimit -v` 4 GB, timeout), at low priority.
- Stage 1, both backends: `rep "a" 100000 ""` 3 ms (was 2.3 s); `acc + ", " + "x"` 100 000 rounds 10–14 ms; a String still held elsewhere (`base`, a list, a variable used after the call) is unchanged; Int `+` in tail calls unchanged.
- New case passes on both backends (with `max-rss-mb: 64` over 200 rounds of a 1 MB String).
- Bootstrap s1 → s4 (0.9.52): s3 and s4 differ in 3 bytes (the pid digits of the temporary file name), fixed point.
- `tests/run.rg strings/ string_append append_through` with s3 and its `stable`: 14 of 14 (llvm 7, x86-64 7).
- Not run, to finish quickly at the user's request: the other case groups, unit tests, libs.
- Installed: s3 and its `stable` in `target/*_candidate` and `bin/`.

## Exact next actions
1. None: done; Solstice told in the shared compiler notes.

## Decisions / open questions
- Only tail positions use the in-place append; `s = s + x` in a block is not covered (no report needs it).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (none)  - [x] docs INDEX updated (no new docs)  - [x] coverage matrix regenerated (not kept in this project)
