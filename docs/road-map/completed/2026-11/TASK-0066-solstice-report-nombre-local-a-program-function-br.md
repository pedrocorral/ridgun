---
id: TASK-0066
title: Solstice report nombre-local: a program function breaks a multi-word call inside an imported module
status: completed
created: 2026-11-10
completed: 2026-11-10
requirements: [FR-COMP-012, FR-COMP-005]
tests: [TS-COMP-012]
security: []
context_files: [docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md, src/main/ridgun/lib/parser.rg]
scope: [src/main/ridgun/lib/parser.rg, tests/run.rg, docs/]
owner: agent-001
claimed: 2026-11-10T08:20:28Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0066 — Solstice report nombre-local: a program function breaks a multi-word call inside an imported module

## Goal (one sentence)
Inside an imported module, a multi-word call whose first word is a local (`err kind eq (kind err) KNone` with a parameter `err`) keeps its name even when the program defines a function named like another of its words (`kind`).

## Plan
- [x] Reproduce `/tmp/ridgun-compiler/2026-11-10/nombre-local/` on 0.9.50: type error (`m.kind called with 4 argument(s)`).
- [x] Module resolution: a local that is the first word of a multi-word function in scope starts that call.
- [x] Toolchain check in `tests/run.rg`, FR-COMP-012 and spec note, bootstrap, suites, install 0.9.51; answer Solstice.

## Progress log (append-only, newest last)
- 2026-11-10: Cause: module resolution (`rewrite call expr`) reads a call whose head is a local as "subject, then a call of the next word" and resolves that word on its own. The program's `kind` makes the record field `kind` a collided name, so the word became `m.kind` and normalisation could no longer join `err kind eq`. Without the program's `kind` the word stayed as written and it worked. Fix: `local head call` tries the scoped multi-word names first (`try consume scoped words`); when the local and at least one following word form a function in scope, the call is resolved like any multi-word call, and the rest of the arguments are resolved as usual (`(kind err)` is still the module's accessor).

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`: `local head call` used by `rewrite call expr` for local-headed calls.
- `tests/run.rg`: toolchain check tc9 (the report's two files).
- `docs/requirements/functional/compiler/FR-COMP-012-module-namespaces-and-qualified-types.md`, `docs/lang/spec.md`: the rule.
- Version 0.9.51: `build.rg`, `ridgunc/main.rg`, `stable/main.rg`.

## Verification performed (command → result, newest last)
All runs capped (`ulimit -v` 4 GB, timeout).
- Stage 1, LLVM and x86-64: the report's `main.rg` prints `True k:a`.
- Bootstrap s1 → s4 (0.9.51, with TASK-0066 and TASK-0067): s3 and s4 differ in 2 bytes (temporary file name), fixed point.
- `tests/run.rg functions/ perf/ names/ lists/ tensors/` with s3 and its `stable`: 136 of 136 after the new case's strict signatures were fixed (llvm 68, x86-64 68).
- Toolchain checks tc8 (lib field accessor) and tc9 (this report) run by hand with s3: `1 []` and `True k:a`.
- Not run, to save CPU at the user's request: the other case groups, `src/test/ridgun` unit tests, libs `stable test`.
- Installed: s3 and its `stable` in `target/*_candidate` and `bin/`.

## Exact next actions
1. None: done; Solstice answered in the shared compiler notes.

## Decisions / open questions
- The known multi-word name wins over reading the local as the subject of a call, as normalisation already did when no other module defined the word.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (none)  - [x] docs INDEX updated (no new docs)  - [x] coverage matrix regenerated (not kept in this project)
