---
id: TASK-0023
title: Remove global ::, context ::, shared ::, and atomic from Ridgun compiler and docs
status: completed
created: 2026-10-24
completed: 2026-10-24
requirements: [FR-COMP-009]
tests: [TS-COMP-005]
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/ast.rg
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/formatter.rg
  - src/test/ridgun/test parallel and tensors.rg
scope:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/*.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
  - src/test/ridgun/*.rg
  - docs/book/**
owner: agent-001
claimed: 2026-10-24T13:01:41Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0023 — Remove global ::, context ::, shared ::, and atomic from Ridgun compiler and docs

## Goal (one sentence)
Remove `global ::`, `context ::`, `shared ::`, `atomic`, and user `with <ctx> = <val> do` from the Ridgun lexer, AST, parser, analyzer, typechecker, compiler, formatter, tests, examples, and multilingual book chapters.

## Plan
- [x] Update `FR-COMP-009` to document the removal of `global ::`, `context ::`, `shared ::`, and `atomic` in favor of explicit parameters and stateful Agents.
- [x] Remove `TokGlobal`, `TokContext`, `TokShared`, `TokAtomic`, `StmtAtomic`, `EAtomicUpdate`, `ELoadContext`, `ELoadShared`, `BLoadCtx`, `BLoadShared`, `BAtomicStore`, and `parse_scoped_global` across `ast.rg`, `lexer.rg`, `parser.rg`, `analyzer.rg`, `typecheck.rg`, `compiler.rg`, and `formatter.rg`.
- [x] Update `src/test/ridgun/test parallel and tensors.rg`, `examples/`, `editors/emacs/ridgun-mode.el`, and Chapter 08 in all 7 language editions of `docs/book/`.
- [x] Bump version to `0.9.18` in `build.rg`, `ridgunc`, and `stable`, rebuild and verify `--strict` checks.
## Progress log (append-only, newest last)
- 2026-10-24: Created and started task per user request to radically remove `global ::`, `context ::`, `shared ::`, and `atomic`.
- 2026-10-24: Removed `global ::`, `context ::`, `shared ::`, and `atomic` across compiler, tests, and books; verified `--strict` checks.
## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`
- `src/main/ridgun/lib/ast.rg`
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/formatter.rg`
- `src/main/ridgun/lib/elf64.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/arm64.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `docs/book/**`
## Verification performed (command → result, newest last)
- `./bin/ridgunc check --strict src/main/ridgun/ridgunc/main.rg` -> 0 errors
- `./bin/ridgunc check --strict src/main/ridgun/stable/main.rg` -> 0 errors
## Exact next actions
1. Mark task done and commit.
## Decisions / open questions
- None (`global ::`, `context ::`, `shared ::`, and `atomic` all removed).
## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
