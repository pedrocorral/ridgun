---
id: TASK-0033
title: Fix RG-093 blocking agent waits, RG-094 Argon2id LLVM opt -O2, and RG-095 multi-file module namespaces
status: completed
created: 2026-10-26
completed: 2026-10-26
requirements: [FR-COMP-009, FR-COMP-012]
tests: [TS-UNIT-001]
security: []
context_files:
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/parser.rg
scope:
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/parser.rg
  - src/test/ridgun/test parallel and tensors.rg
  - src/test/ridgun/test lib and plugins.rg
owner: agent-001
claimed: 2026-10-26T20:48:18Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0033 — Fix RG-093 blocking agent waits, RG-094 Argon2id LLVM opt -O2, and RG-095 multi-file module namespaces

## Goal (one sentence)
Restore concurrent blocking I/O waits on agents (`RG-093`), sub-second Argon2id/PBKDF2 LLVM `-O2` optimization (`RG-094`), and multi-file module namespace isolation (`RG-095`) while keeping `RG-069` at 0 KB leak, and add automated regression tests for all four cases.

## Plan
- [x] Fix `RG-093` in `src/main/ridgun/lib/compiler.rg` (`is_heavy_call_name` for blocking I/O/wait/socket calls and `expand_heavy_fixpoint` without the 200-function cap).
- [x] Fix `RG-094` in `src/main/ridgun/lib/llvm.rg` (restore `/usr/bin/opt -O2` + `/usr/bin/llc -O2` with cached `.rt`/`.lds`).
- [x] Fix `RG-095` in `src/main/ridgun/lib/parser.rg` (preserve enclosing `mod_stack` frames in `set_explicit_mod` and remove false-positive `str_contains s ("module :: " + clean_spec)` skip in `append_own_rg_import_pair`).
- [x] Add automated regression tests for `RG-069`, `RG-093`, `RG-094`, and `RG-095` in `src/test/ridgun/test parallel and tensors.rg` and `src/test/ridgun/test lib and plugins.rg`.
- [x] Bootstrap self-hosted `bin/ridgunc` and `bin/stable` (2 stages) and verify all tests pass.

## Progress log (append-only, newest last)
- 2026-10-26: Diagnosed and fixed `RG-093` (`compiler.rg`), `RG-094` (`llvm.rg`), and `RG-095` (`parser.rg`); added automated regression tests in `src/test/ridgun/test parallel and tensors.rg` and `src/test/ridgun/test lib and plugins.rg`; bootstrapped 2-stage `bin/ridgunc` and `bin/stable` and verified all 4 issues (`RG-069`: 0 KB leak; `RG-093`: 1,002 ms for two 1,000 ms `wait_fd` agents; `RG-094`: 0.79 s Argon2id and 0.38 s PBKDF2 600k; `RG-095`: multi-file `module :: modlib` + `solstice.rglib` with colliding `type Changeset`).

## Files changed (keep current)
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `bin/ridgunc`
- `bin/stable`

## Verification performed (command → result, newest last)
- `./bin/ridgunc run "src/test/ridgun/test parallel and tensors.rg"` → PASS (`RG-093` 2×300 ms blocking poll elapsed 301 ms; `RG-069` 5,000 agent messages 0 leaked blocks).
- `./bin/ridgunc run "src/test/ridgun/test lib and plugins.rg"` → PASS (`RG-095` multi-file `.rg` and `.rglib` `ok:12`; `RG-094` Argon2id `m=19456, t=2, p=1` `< 1,100 ms` `argon2id_ok`).
- `python3 tests/run.py --no-toolchain agents` → 6/6 PASS (`no_leak_50k_messages.rg` 0 KB leak).

## Exact next actions
1. None — task completed.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
