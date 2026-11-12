---
id: TASK-0081
title: A field at different positions in two records is read by the value's own record (libs campo-compartido)
status: completed
created: 2026-11-12
completed: 2026-11-12
requirements: [FR-COMP-001]
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [src/main/ridgun/lib/compiler.rg]
scope: [src/main/ridgun/lib/compiler.rg, tests/cases/records/]
owner: agent-001
claimed: 2026-11-12T17:17:37Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0081 — A shared field name at different positions reads the value's own record

## Goal (one sentence)
`field r`, `r with field = v`, a function-typed field called with arguments and the accessor passed as a value use the position of `r`'s own record.

## Plan
- [x] Collect, per field name, every record that has it. A field with more than one position gets one arm per record in `field_map` (`#fa`/`#fo`/`#fl`/`#fn`).
- [x] The read, set, call and getter-function paths match the record's constructor and use that record's position. No match is a run-time error, never another field.
- [x] Case records/same_field_at_different_positions.rg (the libs repro, `with`, the accessor as a value, and a record of an imported module).
- [x] Full verification, 1.0.8.

## Progress log (append-only, newest last)
- 2026-11-12: libs report campo-compartido. The field index map kept the first record's position for each name, so a field read from a second record read another field. Fields of imported modules were already right (they are qualified per module), and patterns by field name do not exist (patterns are positional). This is a patch, listed in ADR-0009; the typed lowering (TASK-0082) replaces it.

## Files changed (keep current)
- src/main/ridgun/lib/compiler.rg
- tests/cases/records/same_field_at_different_positions.rg
- build.rg, src/main/ridgun/ridgunc/main.rg, src/main/ridgun/stable/main.rg (1.0.8)
- docs/requirements/decisions/ADR-0009-lowering-reads-the-types-of-the-checked-program.md, docs/requirements/decisions/INDEX.md

## Verification performed (command → result, newest last)
- libs repro → `cfg: 5000`, `conn: 5000` on llvm and x86_64-elf (1.0.6 gave `conn: secret`).
- Bootstrap s1→s4: s3 and s4 differ only in the 4 stamp bytes.
- `tests/run.rg` → 310 of 310 (llvm 162, x86_64-elf 148). Unit tests (8 files) → 0 fails. libs `stable test` → 35/35.
- `ridgunc.exe`, `stable.exe` and the new cases build for x86_64-windows. In Wine, records/same_field_at_different_positions.exe prints the expected output.
- In Wine, agent cases hang with no output, as they did with 1.0.3, 1.0.5 and 1.0.6 (`agents/stateless_fifo.rg`). This gap predates this task and is not caused by it.

## Exact next actions
1. None. TASK-0082 (typed lowering) replaces this patch.

## Decisions / open questions
- Known limit (typechecker): an accessor used as a value is typed as the last record with that field, so `[a] map y` with `a :: A` is a compile error when `B` also has `y`. It is a compile error, not a wrong read. TASK-0082 fixes it.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
