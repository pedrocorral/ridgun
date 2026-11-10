---
id: TASK-0071
title: libs report tensor-u8 item 6: read bytes from a pipe reads every byte
status: completed
created: 2026-11-10
completed: 2026-11-10
requirements: [FR-COMP-022] # FR-*/NFR-* this task delivers or touches
tests: [TS-COMP-022]        # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/etc/runtime_ext.md, src/main/ridgun/lib/x86_64.rg] # THE ONLY files an agent must read to work on this task
scope: [docs/etc/runtime_ext.md, src/main/ridgun/lib/x86_64.rg, tests/run.rg, tests/cases/tensors/bytes_read_from_a_pipe.rg] # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-10T18:36:57Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0071 — `read bytes` from a pipe reads every byte

## Goal (one sentence)
`read bytes "/dev/stdin"` with stdin a pipe returns every byte, as with a regular file (libs report tensor-u8 2026-11-09, item 6; items 1-5 were TASK-0065, 0.9.50).

## Plan
- [x] Cause: for a file without a size, `read_bytes` (runtime extension, id 112) counted the bytes, then reopened the path to read them; a pipe is empty the second time.
- [x] Fix: `read_unsized` reads once into an anonymous mapping that doubles with `mremap`, then copies into the tensor and unmaps.
- [x] Rebuild `rtx.bin` from `docs/etc/runtime_ext.md` (unchanged source first gave the embedded bytes exactly), replace `x86 rt ext` code.
- [x] Tests: case `tensors/bytes_read_from_a_pipe.rg` (in-process pipe, empty pipe, procfs); runner check tc11 (200 000 bytes through stdin, past the first 64 KiB mapping).
- [x] Bootstrap, suite, unit tests, libs; install 0.9.56; notes.

## Progress log (append-only, newest last)
- 2026-11-10: re-ran all six report programs with 0.9.55: 1-5 correct, 6 prints 0.

## Files changed (keep current)
- docs/etc/runtime_ext.md, src/main/ridgun/lib/x86_64.rg, FR-COMP-022 §4, tests/run.rg, tests/cases/tensors/bytes_read_from_a_pipe.rg, version 0.9.56

## Verification performed (command → result, newest last)
- new case with 0.9.55 → `runtime error: tensor index out of range` (0 bytes read)
- bootstrap s1..s4 → fixed point (4 bytes, the pid); stable builds
- report programs with 0.9.56 → pipe 5, file 3; items 1 and 4 still correct
- tests/run.rg → 271 of 271 (llvm 141, x86_64-elf 130), tc11 included
- `test parallel and tensors.rg` → passed; libs `stable test` → 34/35 (SMTP only, as before)

## Exact next actions
1. None.

## Decisions / open questions
- Regular files keep the single-allocation path (size from `fstat`).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
