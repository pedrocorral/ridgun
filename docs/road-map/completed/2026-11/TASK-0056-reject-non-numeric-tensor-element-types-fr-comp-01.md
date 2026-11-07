---
id: TASK-0056
title: Reject non-numeric tensor element types (FR-COMP-018)
status: completed
created: 2026-11-07
completed: 2026-11-07
requirements: [FR-COMP-018]
tests: [TS-COMP-018]
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-018-tensor-element-types-are-numeric.md
  - src/main/ridgun/lib/parser.rg
  - tests/cases/tensors/
scope:
  - src/main/ridgun/
  - build.rg
  - tests/cases/tensors/
  - tests/README.md
  - docs/lang/spec.md
  - docs/requirements/functional/compiler/
owner: agent-002
claimed: 2026-11-07T12:46:30Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0056 — Reject non-numeric tensor element types (`FR-COMP-018`)

## Goal (one sentence)
Make a tensor with a non-numeric element type (`Tensor[String * n]`, `Tensor[Bool * n]`, ...) a compile error instead of a tensor that silently stores nothing.

## Plan
- [x] Parser: scan the tokens for `Tensor` / `Tensor_GPU` followed by `[`, `(` and a type name; report every non-numeric element type as a `syntax error` that names the function.
- [x] Acceptance cases in `tests/cases/tensors/`, FR-COMP-018, spec.md, tests/README.md, version 0.9.35.
- [x] Bootstrap to a fixed point; acceptance and `stable test`; install `bin/ridgunc` and `bin/stable`.

## Progress log (append-only, newest last)
- 2026-11-07: Found while reviewing the ridgun-libs `Array A` request: `Tensor[String * 3]` compiled, stored nothing and returned `0`; `Tensor[Bool * 3]` lost `True`. Implemented the parser check and the cases.
- 2026-11-07: Bootstrapped 0.9.35, ran the suites and installed `bin/ridgunc` and `bin/stable`.

## Files changed (keep current)
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/llvm.rg` (cache path), `src/main/ridgun/ridgunc/main.rg`, `src/main/ridgun/stable/main.rg`, `build.rg` (version 0.9.35)
- `docs/requirements/functional/compiler/FR-COMP-018-tensor-element-types-are-numeric.md`, `INDEX.md`
- `docs/lang/spec.md`, `tests/README.md`
- `tests/cases/tensors/*.rg`
- `bin/ridgunc`, `bin/stable`

## Verification performed (command → result, newest last)
- 0.9.34 on `tests/cases/tensors/` → 1/3 (the two error cases build and fail).
- Test compiler (0.9.34 building the new parser) on `tests/cases/tensors/` → 3/3.
- `../libs` tests `test tensor.rg` and `test linalg.rg` (`Real` tensors), built with 0.9.34 and with the test compiler into the scratchpad → both build, identical output, both PASS.
- Bootstrap: 0.9.34 → s1 → s2 → s3 on the new sources; s2 and s3 differ only in 2 bytes, the PID in the linker temporary name.
- `RIDGUNC=s3 bin/ridgunc run tests/run.rg` → 77/79 (3 new cases pass; the same RG-105 / RG-107 `stable deps` failures).
- `RIDGUNC=s3 stable test` (stable 0.9.35) → 6/7, `test lib and plugins.rg` fails as on 0.9.34; `stable check` → 16 modules, 0 errors.
- `../libs` `test tensor.rg` and `test linalg.rg` built with s3 → output identical to 0.9.34.
- Installed `target/` and `bin/` ridgunc and stable 0.9.35.
- `aix docs validate` → 0 errors.

## Exact next actions
1. Close the task.

## Decisions / open questions
- Allowed element types: the integer type names of the type checker (`Int`, `Byte`, `U8`..`U64`, `I8`..`I64`, `Usize`) plus `Real` and `Float`. `Real` tensors stay allowed because `../libs` (`tensor.rg`, `linalg.rg`) uses them.
- Not fixed here: the type checker types every tensor element as `Int`, so `echo t_(1)` on a `Real` tensor prints the raw 64-bit pattern and `t_(1) + 1.0` is a type error. That is a separate change to tensor element typing.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
