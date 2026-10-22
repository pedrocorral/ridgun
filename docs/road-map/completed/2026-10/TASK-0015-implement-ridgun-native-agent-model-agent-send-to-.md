---
id: TASK-0015
title: Implement Ridgun native Agent model (agent, send to, receive from, try receive from, stop) and retire legacy spawn/join
status: completed
created: 2026-10-22
completed: 2026-10-22
requirements:
  - FR-COMP-009
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
scope:
  - src/main/ridgun/
  - src/test/ridgun/
  - docs/
  - harness/
owner: agent-001
claimed: 2026-10-22T15:13:05Z
claimed_by: agent gemini@solarfall
---
# TASK-0015 — Implement Ridgun native Agent model (`agent`, `send ... to`, `receive from`, `try receive from`, `stop`) and retire legacy `spawn`/`join`

## Goal (one sentence)
Implement the Ridgun native Agent concurrency model (`agent`, `send ... to`, `receive from`, `try receive from`, `stop`, `agent alive`, and `Agent` type signatures) across the compiler, VM, and native `x86_64`/`arm64` runtimes (`FR-COMP-009`), and retire legacy `spawn`/`join` across code, harnesses, and books.

## Plan
- [x] Author and register `FR-COMP-009` (`docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`).
- [x] Update `parser.rg` to support `Agent` parameterized types (`Agent`, `Agent In Out`), standalone `send ... to ...` and `stop ...` statements, multi-argument `send a b to ag` tuple packing, parenthesized multi-word function references `(sumar visita)`, `agent`, `stop`, and `agent alive`.
- [x] Update `typecheck.rg`, `analyzer.rg`, and `compiler.rg` to implement stateless and stateful agents (`agent fn`, `agent fn init_state`), `send ... to`, `receive from`, `try receive from`, `stop`, and `agent alive`, and remove `spawn`/`join`.
- [x] Add automated agent tests (stateless, multi-argument, stateful `S M => S`, persistent HTTP session `S M => S R`, `try receive from`, and `stop` / `agent alive`) in `src/test/ridgun/test parallel and tensors.rg`.
- [x] Update `harness/`, `.aix/custom/`, and all 7 book editions (`docs/book/*/01-*.md`, `docs/book/*/07-*.md`, `docs/book/*/INDEX.md` + `build_book.py`) to replace `spawn`/`join` with the native Agent model (`v0.9.12`).

## Progress log (append-only, newest last)
- 2026-10-22: Created and started `TASK-0015` and approved `FR-COMP-009`.
- 2026-10-22: Implemented `FR-COMP-009` across `parser.rg`, `analyzer.rg`, `typecheck.rg`, and `compiler.rg`; added `FR-COMP-009` test suite in `src/test/ridgun/test parallel and tensors.rg`; bumped version to `0.9.12`; updated `harness/`, `.aix/custom/`, and all 7 editions of `docs/book/`; verified 2-stage self-hosting fixed point (`cmp -s target/ridgunc_candidate target/ridgunc_stage3`).

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-009-native-agent-model-and-message-passing.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/analyzer.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `build.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `harness/AGENTS.md`
- `harness/README.md`
- `harness/instructions/ridgun.md`
- `harness/instructions/stable.md`
- `harness/skills/implement-code-ridgun/SKILL.md`
- `harness/skills/implement-code-ridgun/references/cheatsheet.rg`
- `harness/skills/implement-stable-project/SKILL.md`
- `docs/book/{es,ca,gl,eu,en,pt,sv}/01-*.md`
- `docs/book/{es,ca,gl,eu,en,pt,sv}/07-*.md`
- `docs/book/{es,ca,gl,eu,en,pt,sv}/INDEX.md`
- `docs/book/{es,ca,gl,eu,en,pt,sv}/index.html`
- `docs/book/index.html`

## Verification performed (command → result, newest last)
- `cmp -s target/ridgunc_candidate target/ridgunc_stage3` → 0 (`SELF-HOSTING FIXED POINT OK`)
- `./bin/ridgunc check harness/skills/implement-code-ridgun/references/cheatsheet.rg` → 0 errors
- `./bin/stable check && ./bin/stable test` → 0 errors, 5/5 test suites passed

## Exact next actions
1. Close `TASK-0015` and commit `v0.9.12`.

## Decisions / open questions
- Standard functions (`fn ::` and `op ::`) serve directly as agent templates without a separate `actor ::` declaration keyword.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
