---
id: TASK-0096
title: x86-64, ARM64 and Windows use the IR runtime; the byte blobs and C sources go
status: pending             # pending | going-on | blocked | completed
created: 2026-11-15
completed:
requirements: [FR-COMP-022, FR-COMP-023]  # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0013-the-whole-runtime-is-target-neutral-llvm-ir.md, docs/etc/runtime_ext.md]  # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
# TASK-0096 — The other targets use the IR runtime

## Goal (one sentence)
x86-64 (pure and LLVM), ARM64 and Windows run on the target-neutral IR runtime of TASK-0088, and the old runtime pieces are deleted (ADR-0013).

## Plan
- [ ] x86-64 pure encoder: embed the runtime compiled by `llc` as position-independent code at a fixed address, as `rtx.c` is today.
- [ ] LLVM backend: link the same IR; keep the hot functions inlinable; drop the linker-script blob and the duplicated helpers of `llvm.ridgun`.
- [ ] Linux and Windows PAL in IR plus small inline-assembly parts (system calls, `clone`); delete `x86 rt ext`, `win rt ext` and their C sources.
- [ ] ARM64: replace the stubs of `arm64.ridgun` with the runtime compiled for aarch64.
- [ ] The 310 promised behaviours pass on every backend; bootstrap reproducible.

## Progress log (append-only, newest last)
- 2026-11-15: Created with ADR-0013. Needs TASK-0088.

## Exact next actions
1. Start after TASK-0088 is completed.
