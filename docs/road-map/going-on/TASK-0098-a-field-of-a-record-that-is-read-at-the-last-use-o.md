---
id: TASK-0098
title: A field of a record that is read at the last use of the record moves out instead of being cloned (OPT-022); Vonkeep request 1
status: going-on
created: 2026-11-16
completed:
requirements: [FR-COMP-011]            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-16T18:45:11Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0098 — A record field read at the last use of the record moves out

## Goal (one sentence)
A list (or any heap value) held in a field of a record that is rebuilt at each step is not copied at each step: when the old record is not used afterwards, the fields are moved out of it instead of cloned.

## Plan
- [ ] Reproduce with the reporter's file (`/tmp/ridgunc-requests.md`, request 1): list in a record, 1000 / 4000 / 16000 elements; today 9000 / 18500 / 52250 ns per element against 750-1000 for the bare list (ridgunc 1.0.15).
- [ ] Find why: the field read `a_list acc` clones the list (count 2), so the prepend or append sees a shared list and copies it. Confirm in the lowering (`adt_field` is a clone) before changing anything.
- [ ] General solution in the compiler (as OPT-021, not a runtime patch): at the last use of an owned record, its field reads move the field out and drop the empty record. State the rule in `docs/etc/compiler_optimizations.md` (OPT-022) and FR-COMP-011.
- [ ] Test in `tests/cases/perf` with the reproducer (cost per element equal at 1000 and 16000 within 2x) on every backend; correctness cases where the record IS used afterwards (the fields must stay).

## Progress log (append-only, newest last)
- 2026-11-16: Created from the Vonkeep request. Reproduced on 1.0.15 with the same numbers as the report (1.0.10). Cause not yet confirmed in the code.

## Exact next actions
1. Read the lowering of field reads (`compiler.ridgun`) and the ownership of `acc` in `in_record`.
