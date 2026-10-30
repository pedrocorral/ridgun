---
id: TASK-0047
title: Remove underscores from fn/op names and calls across all 7 book editions and docs/lang
status: completed
created: 2026-10-30
completed: 2026-10-30
requirements: [FR-COMP-005]
tests: []
security: []
context_files:
  - docs/book/INDEX.md
  - docs/lang/INDEX.md
scope:
  - docs/book/
  - docs/lang/
owner: agent-001
claimed: 2026-10-30T18:11:54Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only
---
# TASK-0047 — Remove underscores from fn/op names and calls across all 7 book editions and docs/lang

## Goal (one sentence)
Replace all underscore-separated `fn ::`, `op ::`, and builtin function names/calls with canonical space-separated names across all 7 editions of The Ridgun Book (`es`, `ca`, `gl`, `eu`, `en`, `pt`, `sv`) and `docs/lang/` while preserving underscores in local variable names, parameters, record fields, and tensor indices.

## Plan
- [x] Replace underscore-separated `fn`/`op`/builtin names in `docs/book/{es,ca,gl,eu,en,pt,sv}/*.md` while keeping underscores in local variables, parameters, record fields, tensor indices, and explicit negative examples.
- [x] Replace underscore-separated `fn`/`op`/builtin names in `docs/lang/{spec.md,tutorials.md,samples.rg,pal-and-system-libraries.md}`.
- [x] Rebuild all HTML book editions with `bash docs/book/build_book.sh` and validate with `aix docs validate`.

## Progress log (append-only, newest last)
- 2026-10-30: Replaced all underscore-separated `fn`/`op`/builtin names across `docs/book/{es,ca,gl,eu,en,pt,sv}/*.md` and `docs/lang/`, verified all local variable/parameter/field names with `_` were preserved, and rebuilt `docs/book/index.html` and `docs/book/*/index.html`.

## Files changed (keep current)
- `docs/book/es/*.md` and `docs/book/es/index.html`
- `docs/book/ca/*.md` and `docs/book/ca/index.html`
- `docs/book/gl/*.md` and `docs/book/gl/index.html`
- `docs/book/eu/*.md` and `docs/book/eu/index.html`
- `docs/book/en/*.md` and `docs/book/en/index.html`
- `docs/book/pt/*.md` and `docs/book/pt/index.html`
- `docs/book/sv/*.md` and `docs/book/sv/index.html`
- `docs/book/index.html`
- `docs/lang/spec.md`, `docs/lang/tutorials.md`, `docs/lang/samples.rg`, `docs/lang/pal-and-system-libraries.md`

## Verification performed (command → result, newest last)
- Verified zero `fn ::` / `op ::` signatures with `_` remain across `docs/book/*/*.md` and `docs/lang/*` (outside explicit negative examples).
- Verified all local variables, parameters, record fields, and tensor subscripts with `_` remain intact.
- `bash docs/book/build_book.sh && aix docs validate` → 0 errors, 1 warnings.

## Exact next actions
1. Complete `TASK-0047` and commit.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
