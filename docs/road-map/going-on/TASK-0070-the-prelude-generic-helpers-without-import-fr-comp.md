---
id: TASK-0070
title: The prelude: generic helpers without import (FR-COMP-024)
status: going-on
created: 2026-11-10
completed:
requirements: [FR-COMP-024, FR-COMP-012]
tests: [TS-COMP-024]
security: []                # VUL-* to address
context_files: [docs/requirements/functional/compiler/FR-COMP-024-the-prelude.md, docs/requirements/decisions/ADR-0004-the-prelude-ships-with-ridgunc.md]
scope: [src/main/ridgun/lib, src/main/ridgun/stable/main.rg, tests]
owner: agent-001
claimed: 2026-11-10T15:22:06Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0070 — The prelude: generic helpers without import (FR-COMP-024)

## Goal (one sentence)
Ship a prelude of generic list and string helpers with ridgunc, found last in name lookup, then replace the per-type copies in the compiler with it.

## Plan
- [x] Phase A, 0.9.54: `prelude source` in parser.rg, the lowest lookup tier, `ridgunc prelude`, tests, FR-COMP-024 and ADR-0004.
- [ ] Phase B, 0.9.55: the compiler's copies become prelude calls, and stable uses the libs `String` helpers it already imports.

## Progress log (append-only, newest last)
- 2026-11-10: the user asked for the prelude after the duplication count: about 3% of the lines, and 15 copies of "reverse a list".
- 2026-11-10: phase A, first suite → 265/268.
  - `strict/tuple_return_fails` (both backends) failed because of a bug that predates the prelude: `skip to user src marker` skipped past the marker to the end of the tokens. Any program importing an `.rglib` therefore skipped the `--strict` header checks. The prelude made every program look like one. Fixed: the function now returns the tokens after the marker.
  - tc10: the runner redirects only the last command of an `&&` chain, so the check moved into a script.

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`: the prelude, `prelude tier`, `prelude` in the visible set, and the `skip to user src marker` fix.
- `src/main/ridgun/ridgunc/main.rg`: the `prelude` command.
- `tests/cases/lists/prelude_*.rg`, `tests/cases/perf/prelude_helpers_are_linear.rg`, and tc10 in `tests/run.rg`.
- FR-COMP-024 and its INDEX row, ADR-0004 and its INDEX row, `docs/lang/spec.md` Tier 4.

## Verification performed (command → result, newest last)
- Bootstrap: 0.9.53 → s2 → s3 → s4 (4 bytes differ: the pid). After the strict fix, s3 → s5 → s6 (4 bytes).
- New cases on both backends → pass.
  - The perf case runs in 1.5 s. `list reverse` of 1 000 000 elements costs the same as a hand-written copy.
  - Hello world: 134 400 / 107 577 bytes, the same as 0.9.53.
- `tests/run.rg` with s5 → 268/268 (llvm 139, x86_64-elf 129), in 84 s.

## Exact next actions
1. Phase B.

## Decisions / open questions
- The prelude names follow the libs and builtin style (`list …`, `str join`), so the libs per-type copies can become aliases.
- stable imports libs `list`, whose `Int`-only definitions of these names win over the prelude. stable therefore uses `list str nth or` and `list str contains` from libs.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (none)  - [x] docs INDEX updated  - [ ] coverage matrix regenerated
