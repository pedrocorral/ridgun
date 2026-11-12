---
id: TASK-0082
title: Typed lowering: the compiler reads the checked program's types and drops fact strings, marks and run-time shape guesses (ADR-0009)
status: pending             # pending | going-on | blocked | completed
created: 2026-11-12
completed:
requirements: [FR-COMP-001, FR-COMP-009, FR-COMP-020, FR-COMP-022]
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0009-lowering-reads-the-types-of-the-checked-program.md, src/main/ridgun/lib/ast.ridgun, src/main/ridgun/lib/typecheck.ridgun, src/main/ridgun/lib/compiler.ridgun]
scope: [src/main/ridgun/lib/ast.ridgun, src/main/ridgun/lib/typecheck.ridgun, src/main/ridgun/lib/compiler.ridgun]
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0082 — Typed lowering (ADR-0009)

## Goal (one sentence)
The lowering decides from the checked program's types and every patch in ADR-0009's inventory is removed, with the suite unchanged and green.

## Plan
- [ ] Choose the typed form: a type on each expression node, or a type table keyed by node; write it down in ADR-0009 and accept the ADR.
- [ ] `typecheck.ridgun` returns the typed program (lambdas with their inferred types, type variables instantiated where known).
- [ ] `compiler.ridgun` reads the types. Remove the inventory one row at a time, each row its own verified patch version:
  - fact strings and the `"U"` tensor kind;
  - agent step marks and mode 2;
  - field positions;
  - the closure convention;
  - `__unpack2__`;
  - the arity-map marks.
- [ ] Update FR-COMP-001, FR-COMP-009 and FR-COMP-020 as ADR-0009 lists.

## Progress log (append-only, newest last)
- 2026-11-12: Planned after the user asked for general, scalable fixes instead of patches, once the 1.0.x stability fixes are out. Inventory in ADR-0009.

## Files changed (keep current)
-

## Verification performed (command → result, newest last)
-

## Exact next actions
1. Read ADR-0009, then pick the typed form.

## Decisions / open questions
- Patches made before this task lands are added to ADR-0009's inventory in the same commit.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
