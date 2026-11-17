---
id: TASK-0100
title: Cache of the front end by content hash for imported modules (Vonkeep request 5, option A)
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
# TASK — An imported module whose source and dependencies did not change is not

## Goal (one sentence)
An imported module whose source and dependencies did not change is not read, parsed or type-checked again: the front end result is cached by content hash.

## Plan
- [ ] Define the cache key: hash of the module source, hashes of its imports, compiler version.
- [ ] Serialize and load the AST and the type information of a module (versioned format).
- [ ] Invalidate dependents when a module changes.
- [ ] Segment test with a time limit: a small `main` importing a large generated library builds on the second run in a time that does not depend on the library size.
- [ ] Re-measure with `ridgunc build --timings` on a Vonkeep-like program.

## Progress log (append-only, newest last)
- 2026-11-17: Created from Vonkeep request 5 (option A of docs/etc/incremental_and_separate_compilation.md). Self-build front end today: parse 18.9 s, typecheck and analysis 5.4 s of 52 s.

## Exact next actions
1. Read `docs/etc/incremental_and_separate_compilation.md` (options A to D, measurements, acceptance).
