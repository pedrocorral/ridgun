---
id: TASK-0044
title: Ridgun v0.9.30 sink agents, top-level global mailboxes, shared channels, file:line:col syntax diagnostics, and stable --version
status: completed
created: 2026-10-30
completed: 2026-10-30
requirements:
  - FR-COMP-009
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/analyzer.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/stable/main.rg
scope:
  - src/main/ridgun/**
  - src/test/ridgun/**
  - tests/run.rg
  - docs/**
  - harness/**
  - .aix/custom/**
owner: agent-001
claimed: 2026-10-30T11:39:32Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0044 — Ridgun v0.9.30 sink agents, top-level global mailboxes, shared channels, file:line:col syntax diagnostics, and stable --version

## Goal (one sentence)
Implement all `v0.9.30` items from `pendiente-tras-0.9.29.md` and `propuesta-agentes-globales.md`: shared `Channel`/`Agent` descriptors across worker agents, `file:line:col` syntax error diagnostics (`syntax error at ...`), `stable --version` / `-v`, fire-and-forget sink agents (`agent sink`), top-level global sink agents (`agent :: <name> = sink ...`), bounded `mailbox N drop|block`, observability/testing intrinsics (`agent dropped`, `agent flush`, `agent state`, `with agent ... = ... do`), and updated documentation/books/skills.

## Plan
- [x] Exempt `Channel`, `Agent`, and `SinkAgent` descriptors from `ErrUseAfterSend` in `analyzer.rg` while keeping regular payloads affine, and support raw `Channel` in `send_to` and partial-application heavy agent workers in `compiler.rg`.
- [x] Add `file:line:col` syntax error reporting (`syntax error at <file>:<line>:<col>: ...`) in `parser.rg` and `typecheck.rg`.
- [x] Add `stable --version` and `stable -v` support in `stable/main.rg` and bump `ridgunc` and `stable` to `0.9.30`.
- [x] Implement `agent sink`, top-level `agent :: <name> = sink ...`, `mailbox N drop|block`, `drain D`, `agent dropped`, `agent flush`, `agent state`, and `with agent <global> = <spy> do ...` across `lexer.rg`, `parser.rg`, `typecheck.rg`, `compiler.rg`, and `llvm.rg`.
- [x] Bootstrap stage 2 of `ridgunc` and `stable` (`0.9.30`), add unit & toolchain tests, and update `FR-COMP-009`, books (`docs/book/`), skills, and instructions.

## Progress log (append-only, newest last)
- 2026-10-30: Implemented shared `Channel`/`Agent`/`SinkAgent` descriptor tracking in `analyzer.rg` (`"chan:" + v`), raw `Channel` handling in `send_to`, and partial-application heavy agent dispatch in `compiler.rg`; verified `/tmp/ridgun-compiler/2026-10-30/repros/agents_shared_channel.rg`.
- 2026-10-30: Added `locate syntax err in file` (`file:line:col`) in `parser.rg` and `syntax error at <file>:<line>:<col>: ...` formatting in `typecheck.rg`.
- 2026-10-30: Added `--version` and `-v` flags to `stable/main.rg` and bumped `ridgunc`, `stable`, and `build.rg` to `0.9.30`.
- 2026-10-30: Implemented `agent sink`, top-level `agent :: <name> = sink ...`, `mailbox N drop|block`, `drain D`, `agent dropped`, `agent flush`, `agent state`, and `with agent ... = ... do` across `lexer.rg`, `parser.rg`, `typecheck.rg`, `compiler.rg`, and `llvm.rg`.
- 2026-10-30: Bootstrapped `ridgunc` and `stable` `0.9.30`, updated `FR-COMP-009`, `test core language.rg`, `test lib and plugins.rg`, `tests/run.rg`, `docs/book/`, `.aix/custom/`, and `harness/`.

## Files changed (keep current)
- `build.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/llvm.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test core language.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `tests/run.rg`
- `docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`
- `docs/book/build_book.sh` and `docs/book/*/index.html`, `docs/book/*/07-*.md`
- `.aix/custom/` and `harness/`

## Verification performed (command → result, newest last)
- `./bin/ridgunc check /tmp/ridgun-compiler/2026-10-30/repros/agents_shared_channel.rg` → 0 error(s), runs and prints `sent`, `A: channel drained 40 of 40`, `workers: 40`.
- `./bin/ridgunc --version` → `ridgunc 0.9.30`
- `./bin/stable --version` / `./bin/stable -v` → `stable 0.9.30`
- `./bin/stable check` → 14/14 modules passed (0 errors)
- `./bin/stable test` → 6/6 test suites passed (0 failures)

## Exact next actions
1. Close `TASK-0044` and commit all changes.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
