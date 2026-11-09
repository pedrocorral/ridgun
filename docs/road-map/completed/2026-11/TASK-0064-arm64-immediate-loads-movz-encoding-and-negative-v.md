---
id: TASK-0064
title: ARM64 immediate loads: MOVZ encoding and negative values
status: completed
created: 2026-11-09
completed: 2026-11-09
requirements: [FR-COMP-004]
tests: []
security: []
context_files: [src/main/ridgun/lib/arm64.rg, src/test/ridgun/test cross platform targets.rg]
scope: [src/main/ridgun/lib/arm64.rg, src/test/ridgun/]
owner: agent-001
claimed: 2026-11-09T17:39:39Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0064 — ARM64 immediate loads: MOVZ encoding and negative values

## Goal (one sentence)
`arm64 mov imm64` loads any 64-bit `Int` exactly, so every constant on the ARM64 backend is right (FR-COMP-004).

## Plan
- [x] Halfwords of the two's complement for any `Int` (negative values gave a wrong upper half: `-1` loaded `0x00000000FFFFFFFF`).
- [x] MOVZ base `0xD2800000` (it was `0xD0000000`, which is ADRP: every constant load started with a wrong instruction since TASK-0006).
- [x] Check the other encoder formulas in `arm64.rg` against `llvm-mc`.
- [x] Regression test in `test cross platform targets.rg`; fix that file's old build error.
- [x] Bootstrap, suites, install 0.9.49.

## Progress log (append-only, newest last)
- 2026-11-09: Found while fixing the same class of bug in `elf64.rg` `u64 le` (TASK-0063). `arm64 mov imm64` cut the value with truncating division, so for a negative value the upper 32 bits were 0 whenever the lower 32 bits were not. Checking the bytes against the Arm encoding also showed the MOVZ base was wrong.
- 2026-11-09: `arm64 imm16 at v k` gives halfword k of the two's complement (negative v: 65535 minus the halfword of `-v - 1`). MOVZ base `3531603968`. No ARM64 machine or emulator here: checked by encoding, not by running ARM64 binaries.
- 2026-11-09: `test cross platform targets.rg` did not build since `lower program to native` took a second argument (`lower_sample_prog` type error, known since 0.9.46); now it passes `[]` and the file runs.

## Files changed (keep current)
- `src/main/ridgun/lib/arm64.rg`: `arm64 movz` base, `arm64 mov imm64` through `arm64 imm16 at` / `arm64 imm16 scale`.
- `src/test/ridgun/test cross platform targets.rg`: `lower sample prog` call, `test arm64 immediates`.
- Version 0.9.49: `build.rg`, `ridgunc/main.rg`, `stable/main.rg`, LLVM cache paths in `llvm.rg`.

## Verification performed (command → result, newest last)
All runs capped (`ulimit -v` 4 GB, timeout).
- `llvm-mc -triple=aarch64 -show-encoding` on own one-line sources: MOVZ, MOVK, MOV reg, MOV from SP, LDR slot, ADD SP, B, BL, CBZ, CBNZ: the formulas in `arm64.rg` give the same words (MOVZ only after the fix).
- Probe program importing `arm64`: 16 values (0, 1, -1, -2, -3, ±2^16 edges, ±2^32 edges, ±0x0123456789ABCDEF, Int maximum and minimum) give the MOVZ/MOVK words of a Python reference; before the fix 16 of 16 differed.
- `test cross platform targets`: passes on LLVM and x86-64 (did not build before).
- Bootstrap bin/ridgunc (0.9.48) -> s1 -> s2 -> s3 -> s4 (0.9.49): s3/s4 differ only in the `__rg_llvm_<pid>.ll` temporary name.
- `RIDGUNC=s3 STABLE=stable_n ridgunc run tests/run.rg`: first run 243 of 244, `perf/bytes_crc32_and_conversions.rg` on x86-64 stopped by the 5 s case timeout with no output; not reproduced: 150 sequential and 160 parallel (16 at a time) direct runs all right in about 0.82 s, the bytes cases through the runner 3 times 14 of 14, second full run 244 of 244 (LLVM 126, x86-64 118).
- `test basics`, `test core language`, `test strings`, `test parallel and tensors`, `test llvm codegen`, `test cross platform targets`: pass on LLVM and x86-64.
- Installed `bin/ridgunc` and `bin/stable` 0.9.49 from `target/` candidates.

## Exact next actions
None.

## Decisions / open questions
- The hard-coded instruction words of the ARM64 runtime (`u32 le <constant>`) were not audited here; only the encoder formulas were.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (none)  - [x] docs INDEX updated (no new docs)  - [x] coverage matrix regenerated (not kept in this project)
