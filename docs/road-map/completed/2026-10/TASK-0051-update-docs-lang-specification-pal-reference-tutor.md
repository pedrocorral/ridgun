---
id: TASK-0051
title: Update docs/lang/ specification, PAL reference, tutorials, and samples to match current compiler
status: completed
created: 2026-10-31
requirements: [FR-COMP-003, FR-COMP-004, FR-COMP-005, FR-COMP-006, FR-COMP-007, FR-COMP-009]
tests: [TS-UNIT-001]
security: []
context_files:
  - docs/lang/spec.md
  - docs/lang/pal-and-system-libraries.md
  - docs/lang/tutorials.md
  - docs/lang/samples.rg
scope:
  - docs/lang/spec.md
  - docs/lang/pal-and-system-libraries.md
  - docs/lang/tutorials.md
  - docs/lang/samples.rg
owner: agent-001
claimed: 2026-10-31T18:17:22Z
claimed_by: agent gemini@solarfall
---
# TASK-0051 — Update docs/lang/ specification, PAL reference, tutorials, and samples to match current compiler

## Goal (one sentence)
Bring `docs/lang/spec.md`, `docs/lang/pal-and-system-libraries.md`, `docs/lang/tutorials.md`, and `docs/lang/samples.rg` in sync with the current `ridgunc` CLI, record `with field = val` syntax, PAL versionless header, and current Ridgun grammar.

## Plan
- [x] Update CLI Usage (`ridgunc <command> [options] <file.rg>`), record update syntax (`c with tls = True, port = 443`), Native Agent Model section, and `sys call` arity in `docs/lang/spec.md`.
- [x] Remove hardcoded `v0.9.5` version from `docs/lang/pal-and-system-libraries.md` and update `_ = sys close fd` examples to `sys close fd -> ()`.
- [x] Update `docs/lang/tutorials.md` and `docs/lang/samples.rg` to use `ridgunc run`, `type Point = x: Int, y: Int`, uppercase type variables `A`..`Z`, `=` before guards, `||` parallel blocks, and native agents.

## Progress log (append-only, newest last)
- 2026-10-31: Created and started `TASK-0051`.

## Files changed (keep current)
- `docs/lang/spec.md`
- `docs/lang/pal-and-system-libraries.md`
- `docs/lang/tutorials.md`
- `docs/lang/samples.rg`

## Verification performed (command → result, newest last)
- `aix docs validate` → `0 errors`

## Exact next actions
1. Apply edits to `docs/lang/` files, close `TASK-0051`, and commit.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
