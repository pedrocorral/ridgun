---
id: TASK-0009
title: Support natural-language spaces in fn ::, built-in calls, filenames, and update docs and books
status: completed
created: 2026-10-21
completed: 2026-10-21
requirements:
  - FR-COMP-005
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/stable/main.rg
  - src/test/ridgun/test core language.rg
scope:
  - src/main/ridgun/
  - src/test/ridgun/
  - build.rg
  - harness/
  - docs/
  - README.md
owner: agent-001
claimed: 2026-10-21T11:56:05Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only
---
# TASK-0009 — Support natural-language spaces in `fn ::`, built-in calls, filenames, and update docs and books

## Goal (one sentence)
Deliver `FR-COMP-005` AC-5 by supporting natural-language spaces (`" "`) instead of underscores (`_`) in `fn ::` declarations and calls, built-in/test calls (`assert equals`, `str len`, `read file`), higher-order function arguments (`map double val xs`), and `.rg` filenames (`test basics.rg`, `test core language.rg`, `test parallel and tensors.rg`, `test strings.rg`), and updating `harness/`, `README.md`, `docs/lang/spec.md`, and the Ridgun books across all 7 languages.

## Plan
- [x] Update `docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md` with AC-5.
- [x] Update `src/main/ridgun/lib/parser.rg`, `src/main/ridgun/lib/typecheck.rg`, and `src/main/ridgun/stable/main.rg` to support multi-word `fn ::` declarations, space-separated built-in/test calls, first-class multi-word function arguments, and space-separated `.rg` filenames.
- [x] Rename `src/test/ridgun/test_*.rg` to `test basics.rg`, `test core language.rg`, `test parallel and tensors.rg`, and `test strings.rg`, and update `build.rg` and `src/test/ridgun/test.rg` to use natural spaces.
- [x] Update `harness/`, `.aix/custom/`, `.agents/skills/`, `README.md`, `docs/lang/spec.md`, and Chapters 02 and 06 across all 7 languages of the Ridgun book (`sv`, `es`, `en`, `pt`, `ca`, `gl`, `eu`).
- [x] Bootstrap Stage 1 & Stage 2 `target/ridgunc` and `target/stable`, and verify `./target/stable check` and `./target/stable test`.

## Progress log (append-only, newest last)
- 2026-10-21: Implemented multi-word `fn ::`, space-separated built-in/test calls, first-class multi-word function references, and space-named `.rg` files in `parser.rg`, `typecheck.rg`, and `stable/main.rg`; renamed test suites and updated `build.rg`, `harness/`, `README.md`, `docs/lang/spec.md`, and the Ridgun book in all 7 languages.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-005-shared-adt-constructors-and-expand-type.md`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/stable/main.rg`
- `build.rg`
- `src/test/ridgun/test.rg`
- `src/test/ridgun/test basics.rg`
- `src/test/ridgun/test core language.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test strings.rg`
- `harness/instructions/ridgun.md`
- `harness/skills/implement-code-ridgun/SKILL.md`
- `harness/skills/implement-code-ridgun/references/cheatsheet.rg`
- `README.md`
- `docs/lang/spec.md`
- `docs/book/**/02-*.md`
- `docs/book/**/06-*.md`

## Verification performed (command → result, newest last)
- `./target/ridgunc build src/main/ridgun/ridgunc/main.rg -o target/ridgunc.stage1 && ./target/ridgunc.stage1 build src/main/ridgun/ridgunc/main.rg -o target/ridgunc.stage2 && cmp -s target/ridgunc.stage1 target/ridgunc.stage2` → Stage 1 and Stage 2 identical (`0` exit code).
- `./target/stable check` → Checked 13 module(s) — 0 errors.
- `./target/stable test` → Passed 4/4 space-named test suite(s) — 0 failures.

## Exact next actions
1. Complete `TASK-0009` and run `aix docs validate`.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
