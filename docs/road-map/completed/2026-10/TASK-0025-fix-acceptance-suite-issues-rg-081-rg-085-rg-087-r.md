---
id: TASK-0025
title: Fix acceptance suite issues (RG-081, RG-085, RG-087, RG-089, RG-090)
status: completed
created: 2026-10-24
completed: 2026-10-24
requirements: [FR-COMP-007, FR-COMP-009, FR-VM-001]
tests: [TS-COMP-009, TS-VM-001]
security: []
context_files:
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/elf64.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/test/ridgun/test lib and plugins.rg
  - docs/lang/pal-and-system-libraries.md
  - docs/requirements/functional/compiler/FR-COMP-007-low-level-posix-fd-poll-syscalls-and-with-timeout-blocks.md
scope:
  - src/main/ridgun/lib/**
  - src/main/ridgun/ridgunc/**
  - src/test/ridgun/**
  - docs/**
owner: agent-001
claimed: 2026-10-24T19:44:21Z
claimed_by: agent gemini@solarfall
---
# TASK-0025 — Fix acceptance suite issues (RG-081, RG-085, RG-087, RG-089, RG-090) & add PAL `sys_pipe` / `sys_waitpid`

## Goal (one sentence)
Fix all remaining Solstice acceptance suite failures (`RG-081`, `RG-087`, `RG-089`, `RG-090`, plus `global ::` declaration rejection), meet the `RG-085` list append/prepend performance proposal, and add native `sys_pipe` and `sys_waitpid` PAL built-ins for `posix.rg`.

## Plan
- [x] Reject unknown top-level declarations (`RG-090`) and `global ::` declarations in `parser.rg` / `typecheck.rg`.
- [x] Fix `str_slice` byte slicing consistency (`RG-087`) so `str_slice s 0 k + str_slice s k (str_len s) == s` for all `k` in `0..str_len s`.
- [x] Fix `read_file` / `bytes_from_list` byte preservation (`RG-089`) so `read_file` returns the exact bytes written by `write_file` (`0..255`).
- [x] Fix `ridgunc build -o <out>` into a missing parent directory (`RG-081`) to verify or fail with non-zero exit if the output file cannot be written.
- [x] Optimize `([x] :: acc)` single-element list prepend in `compiler.rg` (`RG-085`) so both `acc :: [x]` and `[x] :: acc` run in O(1) amortized time (< 1000 ms for 20,000 elements).
- [x] Add `sys_pipe : => (Int, Int)` (`b_id 86`, `__NR_pipe = 22`) and `sys_waitpid : Int Int => (Int, Int)` (`b_id 87`, `__NR_wait4 = 61`, with `WIFEXITED`/`WEXITSTATUS` and `WIFSIGNALED`/`128 + WTERMSIG` decoding) to `parser.rg`, `typecheck.rg`, `compiler.rg`, `x86_64.rg`, and PAL docs/tests.
- [x] 3-stage self-host `ridgunc` and `stable`, verify `python3 tests/run.py` and `./bin/stable test`.
## Progress log (append-only, newest last)
- 2026-10-24: Implemented `RG-090` unknown top-level declaration and `global ::` rejection in `parser.rg` / `typecheck.rg` (while preserving `RGC1` headers and quoted `import "..."` paths), `RG-081` missing output directory failure check in `elf64.rg`, `RG-085` recursive `EBin OpConcat` TCO move lowering in `compiler.rg`, `RG-089` raw byte preservation in `read_file` (`slot55c`), `RG-087` exact byte-indexed `str_slice` via `rg_new_str` (`slot55b`), and native `sys_pipe` (`b_id 86`) + `sys_waitpid` (`b_id 87`) built-ins in `x86_64.rg`. Verified 3-stage self-host (`stage2 == stage3`, SHA-256 `0120be5203c1c77a896c528db0b300f00826c36822bcec120217cb7bc87d4509`), `python3 tests/run.py` (40/40 passed, 0 proposals unmet), and `./bin/stable test` (5/5 test suites passed).
## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/elf64.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `docs/lang/pal-and-system-libraries.md`
- `docs/requirements/functional/compiler/FR-COMP-007-low-level-posix-fd-poll-syscalls-and-with-timeout-blocks.md`
- `bin/ridgunc`
- `bin/stable`
## Verification performed (command → result, newest last)
- `sha256sum target/ridgunc_stage2 target/ridgunc_stage3` → `0120be5203c1c77a896c528db0b300f00826c36822bcec120217cb7bc87d4509` (identical)
- `./bin/stable test` → `Passed 5/5 test suite(s) — 0 failures.`
- `python3 tests/run.py` → `40 of 40 promised behaviours passed` (0 proposals unmet)
## Exact next actions
1. Complete `TASK-0025` and commit changes.
## Decisions / open questions
- None.
## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
