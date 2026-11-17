---
id: TASK-0101
title: Cache of the lowered code by content hash (Vonkeep request 5, option B)
status: pending             # pending | going-on | blocked | completed
created: 2026-11-17
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK — The lowered native code of a function is cached by the hash of the fun

## Goal (one sentence)
The lowered native code of a function is cached by the hash of the function and of everything its lowering read, so a change lowers only what depends on it.

## Plan
- [ ] Make the lowering report what each function read from the global tables (callee signatures, borrow masks, field map).
- [ ] Key the cache by the function text and those reads.
- [ ] Segment test: a change of one function lowers only it and its dependents.

## Progress log (append-only, newest last)
- 2026-11-17: Created from Vonkeep request 5 (option B). Lowering is 18.4 s of the 52 s self-build.

## Exact next actions
1. Read `docs/etc/incremental_and_separate_compilation.md` (options A to D, measurements, acceptance).
