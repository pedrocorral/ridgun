---
id: TASK-0074
title: Compiler defect report 2026-11-11: _ in pair bindings, not/with in names, stable run rebuild
status: completed
created: 2026-11-11
completed: 2026-11-11
requirements: [FR-COMP-005, FR-COMP-011, FR-TOOL-002] # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: [src/main/ridgun/lib/parser.rg, src/main/ridgun/stable/main.rg, tests] # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-11T15:24:56Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0074 — Compiler defect report 2026-11-11 (/tmp/ridgun-compiler-defects.md)

## Goal (one sentence)
Fix the three defects of the report: `_` in a pair binding, `not`/`with` inside function names, `stable run` with a stale binary.

## Plan
- [x] 1. `_, n = f a` released a value other variables still held (the original record's lists came back empty). Cause: the pair binding desugars to `StmtMut "_" (tmp_(0))`; only `StmtLet "_"` had the discard path, so `_` became a variable outside the collected locals. Fix: the desugaring binds nothing for `_`; that part is released with the tuple.
- [x] 2. `not`/`with` inside a `fn ::` name: a pass before parsing turns those tokens into words wherever the tokens spell a declared name holding them; elsewhere they keep their meaning.
- [x] 3. `stable run` only built when the binary did not exist, so it always ran the previous program after a change. Now it rebuilds unless a content stamp (`<binary>.stamp`: hash of sources, paths and compiler version) matches; it also creates target/.
- [x] Cases records/pair_discard_keeps_original.rg, names/not_and_with_in_function_names.rg; runner check tc13 (tests/toolchain/stable_run_rebuilds.sh); spec.md, FR-TOOL-002 AC6.
- [x] Bootstrap, suite, unit tests, libs; install 0.9.59; notes.

## Progress log (append-only, newest last)
- 2026-11-11: reproduced 1 and 2 on 0.9.58; item 1 also fails with two `_` (the report said that variant worked). Item 3 is not a timing issue: run never rebuilt an existing binary.

## Files changed (keep current)
- src/main/ridgun/lib/parser.rg, src/main/ridgun/stable/main.rg, docs/lang/spec.md, FR-TOOL-002, tests/run.rg, tests/toolchain/stable_run_rebuilds.sh, two cases, version 0.9.59

## Verification performed (command → result, newest last)
- both cases with 0.9.58 → wrong output / build error; with stage 1 → expected, under --strict
- stable_run_rebuilds.sh with the new stable → FIRST_OK REBUILT_OK CACHED_OK; with 0.9.58 → exit 1
- bootstrap s3/s4 → fixed point (3 bytes); tests/run.rg → 278 of 279 while another session was compiling (suite took 1 244 s): perf/field_reads_and_small_calls.rg [x86_64-elf] timed out; the same case runs in the same time with 0.9.58 and 0.9.59, and perf/ passed 14 of 14 twice afterwards
- all 8 `src/test/ridgun/test*.rg` → passed; libs `stable test` → 35/35

## Exact next actions
1. None.

## Decisions / open questions
- `not`/`with` become words only where the tokens spell a declared name exactly, so a name always wins over the operator reading, as for and/or/xor since 0.9.50.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
