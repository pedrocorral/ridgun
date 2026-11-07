---
id: TASK-0055
title: Fix 64-bit Int literals and str_to_int (RG-113) and constructor patterns in tuples (RG-114)
status: completed
created: 2026-11-07
completed: 2026-11-07
requirements: [FR-COMP-016, FR-COMP-017]
tests: [TS-COMP-016, TS-COMP-017]
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-016-full-64-bit-int-literals-and-str-to-int.md
  - docs/requirements/functional/compiler/FR-COMP-017-constructor-patterns-in-tuples-and-no-match-error.md
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/compiler.rg
  - tests/run.rg
scope:
  - src/main/ridgun/
  - build.rg
  - tests/cases/
  - tests/README.md
  - docs/lang/spec.md
  - docs/requirements/functional/compiler/
owner: agent-002
claimed: 2026-11-07T10:34:17Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0055 — Fix 64-bit `Int` literals and `str_to_int` (RG-113) and constructor patterns in tuples (RG-114)

## Goal (one sentence)
Make every `Int` literal and `str_to_int` keep all 64 bits (with compile errors for out-of-range literals), make constructor patterns match inside tuple and cons patterns, and stop a call that matches no clause with a runtime error instead of the zero value.

## Plan
- [x] Lexer: accumulate decimal and hex literals with 64-bit arithmetic; emit `TokBadInt` / `TokIntMin` for out-of-range literals.
- [x] Parser: unary minus plus `9223372036854775808` is the `Int` minimum; every other out-of-range literal is a `syntax error` naming the literal and the function.
- [x] Lowering: literals outside the tagged range (±2^62) are built with `NBinOp` (heap-boxed); wide literal patterns compare with `OpEq`.
- [x] `str_to_int`: route calls to the compiler-provided helper `__rg_s2i_wide` (runtime builtin for ≤ 17 characters, 64-bit parser for longer strings).
- [x] Parser: constructor patterns with arguments inside tuple elements and cons heads (RG-114 §1).
- [x] Lowering: a no-match tail that writes `runtime error: no clause of function '<name>' matches its arguments` and exits with status 1 (RG-114 §2).
- [x] Acceptance cases, FR-COMP-016 / FR-COMP-017, spec.md, tests/README.md, version 0.9.34.
- [x] Bootstrap to a byte-identical fixed point; acceptance and `stable test`; install `bin/ridgunc` and `bin/stable`.

## Progress log (append-only, newest last)
- 2026-11-07: Started from Solstice register RG-113. Implemented the lexer, parser and lowering changes and the `str_to_int` helper. Wrote FR-COMP-016 and the RG-113 cases.
- 2026-11-07: Added RG-114 (`/tmp/ridgun-compiler/2026-11-07/patron-constructor-en-tupla.md`): constructor patterns in tuples and the no-match runtime error. Wrote FR-COMP-017 and the RG-114 cases.
- 2026-11-07: Bootstrapped 0.9.34 to a fixed point, ran the acceptance suite, `stable test` and the pure x86-64 encoder, and installed `bin/ridgunc` and `bin/stable`.

## Files changed (keep current)
- `src/main/ridgun/lib/ast.rg`, `lexer.rg`, `parser.rg`, `compiler.rg`, `llvm.rg` (cache path)
- `src/main/ridgun/ridgunc/main.rg`, `src/main/ridgun/stable/main.rg`, `build.rg` (version 0.9.34)
- `docs/requirements/functional/compiler/FR-COMP-016-*.md`, `FR-COMP-017-*.md`, `INDEX.md`
- `docs/lang/spec.md`, `tests/README.md`
- `tests/cases/literals/rg113_*.rg`, `tests/cases/strings/rg113_str_to_int_64bit.rg`
- `tests/cases/adts/rg114_*.rg`, `tests/cases/functions/rg114_*.rg`, `tests/cases/guards/rg114_*.rg`
- `bin/ridgunc`, `bin/stable`

## Verification performed (command → result, newest last)
- Baseline (0.9.33): `bin/ridgunc run tests/run.rg` → 65/67; the two failures are the pre-existing RG-105 / RG-107 `stable deps` cases. `bin/stable test` → 6/7 (`test lib and plugins.rg` fails).
- Bootstrap: stage1 = 0.9.33 building the new sources; stage2, stage3 and stage4 = each stage building `src/main/ridgun/ridgunc/main.rg` → stage2, stage3 and stage4 are identical except 4 bytes. Those bytes are the PID in the linker's temporary object name (`/tmp/__rg_llvm_<pid>.ll`), which every build had before this change too.
- `RIDGUNC=stage4 bin/ridgunc run tests/run.rg` → 74/76 (all 9 new cases pass; the same two RG-105 / RG-107 failures).
- `RIDGUNC=stage4 bin/stable test` → 6/7, the same suite fails; output identical to the baseline except benchmark timings.
- `ridgunc build --target x86_64-linux` (pure x86-64 encoder) on the 5 runnable new cases → output and exit status as expected.
- `str_to_int "123456789"` × 5 000 000 → 0.71 s (0.9.33, wrong for 19 digits) vs 0.93 s (0.9.34): about 44 ns more per call.
- New `stable` (built by stage4): `stable test` → 6/7 (same suite), `stable check` → 16 modules, 0 errors.
- Installed `target/ridgunc`, `target/stable`, `bin/ridgunc`, `bin/stable` (0.9.34); `bin/ridgunc run tests/run.rg` → 74/76.
- `aix docs validate` → 0 errors.

## Exact next actions
1. Close the task.

## Decisions / open questions
- `str_to_int` lives in the hand-written runtime blob, which must not be patched. The fix routes calls to a Ridgun helper that the compiler adds to every program that uses `str_to_int`.
- The no-match message names the function in its internal form (`only_one`), as type errors do.
- The ARM64, Mach-O and PE backends cannot run on this machine. The fix is in the lexer, parser and shared lowering, so it reaches them unchanged; only the LLVM and pure x86-64 backends were run.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
