---
id: TASK-0022
title: Implement first-class typed Tensor[...], subscript views, map f in m_(i,), and native bitwise operations
status: completed
created: 2026-10-23
completed: 2026-10-23
requirements:
  - FR-COMP-010
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-010-typed-tensors-einstein-map-and-native-bitwise-ops.md
  - src/main/ridgun/lib/types.rg
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/formatter.rg
  - src/test/ridgun/test parallel and tensors.rg
scope:
  - src/main/ridgun/lib/*.rg
  - src/test/ridgun/test parallel and tensors.rg
owner: agent-001
claimed: 2026-10-23T12:55:46Z
claimed_by: agent gemini@solarfall
---
# TASK-0022 — Implement first-class typed Tensor[...], subscript views, map f in m_(i,), and native bitwise operations

## Goal (one sentence)
Implement first-class typed `Tensor[...]` (`Tensor[Byte]`, `Tensor[T^k]`, `Tensor[T * d1 * ... * dk]`), pattern matching with dimension binding, subscript indexing/views (`v_(ia) = ...`, `m_(r,)`, `m_(,c)`), axis-aware `map`/`||map` and in-place `map f in m_(i,)` / `map f in m_(,j)`, and native 1-cycle CPU bitwise operations (`xor`, `and`, `or`, `not`, `shl`, `shr`, `rotr`, `rotl`).

## Plan
- [x] Extend `types.rg`, `lexer.rg`, and `parser.rg` for `Tensor[...]` type signatures, creation, pattern matching, subscript views/assignments (`v_(ia) = ...`, `m_(i,)`, `m_(,j)`), `map f in m` / `||map f in m`, and bitwise operators (`xor`, `and`, `or`, `not`, `shl`, `shr`, `rotr`, `rotl`).
- [x] Extend `typecheck.rg` and `formatter.rg` for `Tensor[...]` types, dimension-binding patterns, bitwise operators, and tensor `map` / `map ... in`.
- [x] Implement native 64-bit integer/byte tensor storage, views/slicing, axis-aware `map` / `map ... in` (`_(i,)`, `_(,j)`, `_ij`), and 1-cycle CPU bitwise instructions in `compiler.rg` and `x86_64.rg` / `vm.rg`.
- [x] Decouple `stable` (`ADR-0001`), fix `.stable/deps/` and transitive `.rglib` / `.rg` module resolution in `parser.rg`, and add regression tests in `src/test/ridgun/test lib and plugins.rg` and `src/test/ridgun/test parallel and tensors.rg`.

## Progress log (append-only, newest last)
- 2026-10-23: Created `FR-COMP-010` and started `TASK-0022`.
- 2026-10-23: Completed `FR-COMP-010`, `ADR-0001` (`stable` decoupling), fast prefix-filtered mixfix normalization, `.stable/deps/` & transitive local/external import resolution in `parser.rg`, and regression tests (`test parallel and tensors.rg`, `test lib and plugins.rg`).

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-010-typed-tensors-einstein-map-and-native-bitwise-ops.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `docs/requirements/decisions/ADR-0001-decouple-stable-from-ridgunc-compiler-internals.md`
- `docs/requirements/decisions/INDEX.md`
- `src/main/ridgun/lib/types.rg`
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/formatter.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test parallel and tensors.rg`
- `src/test/ridgun/test lib and plugins.rg`

## Verification performed (command → result, newest last)
- `./bin/ridgunc check src/main/ridgun/lib/parser.rg` -> 0 errors (6.2s)
- `./bin/ridgunc check src/main/ridgun/stable/main.rg` -> 0 errors (0.8s)
- `./bin/ridgunc build "src/test/ridgun/test parallel and tensors.rg" -o target/test_tensors && ./target/test_tensors` -> 100% passed (including BlaMka `blamka g` / `blamka p16` on `Tensor[U64 * 8 * 16]`)
- `./bin/ridgunc build "src/test/ridgun/test lib and plugins.rg" -o target/test_lib && ./target/test_lib` -> 100% passed in 16s (including `.stable/deps/` transitive resolution test `6c-bis`)
- `aix docs validate` -> 0 errors

## Exact next actions
1. Ready to close `TASK-0022` or proceed with next user task.

## Decisions / open questions
- Recorded `ADR-0001` (Decouple `stable` CLI from `ridgunc` Compiler Internals).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
