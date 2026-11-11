---
id: TASK-0075
title: Opaque types: export a type without its constructors (FR-COMP-025)
status: completed
created: 2026-11-11
completed: 2026-11-11
requirements: [FR-COMP-025] # FR-*/NFR-* this task delivers or touches
tests: [TS-COMP-025]        # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: [src/main/ridgun/lib/parser.rg, src/main/ridgun/lib/typecheck.rg, src/main/ridgun/lib/formatter.rg, tests/cases/opaque] # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-11T20:27:31Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0075 — Opaque types (feature request /tmp/ridgun-feature-opaque-types.md), released as 1.0.0

## Goal (one sentence)
A module can export a type while keeping its constructors, fields, `with` and `expand type` to itself.

## Plan
- [x] Syntax: `opaque type T = ...` (option A of the request; ADR-0006).
- [x] The parser leaves a marker per opaque type; name resolution builds a table of the resolved constructor, field and type names with their owning module.
- [x] Each function is checked after its names are resolved in its own module context: constructor calls and values, constructor patterns, positional record construction, accessors (not shadowed by a local) and `with` fields of another module's opaque type are `visibility error`s. `expand type` of another module's opaque type too.
- [x] Formatter, `stable` header detection and the bracket-error locator know the keyword.
- [x] FR-COMP-025, ADR-0006, spec §module namespaces item 4, agent instructions and the code-ridgun skill.
- [x] Seven cases in tests/cases/opaque.
- [x] Version 1.0.0 (the user named this release 1.0.0 if the tests pass).

## Progress log (append-only, newest last)
- 2026-11-12: implemented, cases pass with stage 1; full bootstrap and suites run.

## Files changed (keep current)
- src/main/ridgun/lib/parser.rg, typecheck.rg, formatter.rg; src/main/ridgun/stable/main.rg; ridgunc/main.rg; build.rg
- docs: FR-COMP-025, ADR-0006, both INDEX files, docs/lang/spec.md, .aix/custom instructions and skill
- tests/cases/opaque/*.rg

## Verification performed (command → result, newest last)
- stage-1 compiler on the 7 cases → 6 rejected with the expected message, 1 builds and prints the expected output.
- bootstrap s1→s4 fixed point (3 bytes); suite 293/293 (llvm 153, x86_64-elf 140); 8 unit test files 0 fails; libs 35/35 → installed as 1.0.0.

## Exact next actions
1. None.

## Decisions / open questions
- Printing (`echo`, interpolation) still shows the content: the printer is shared runtime machine code in every backend. Recorded as a known limit in FR-COMP-025.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [ ] coverage matrix regenerated
