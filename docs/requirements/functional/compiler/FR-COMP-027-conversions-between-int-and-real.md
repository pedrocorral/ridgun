---
id: FR-COMP-027
title: Conversions between Int and Real
status: implemented
priority: must
created: 2026-11-17
updated: 2026-11-17
depends_on:
  - FR-COMP-004
related:
  - ADR-0013
verified_by: []
---
# FR-COMP-027 — Conversions between `Int` and `Real`

## Statement
The language has no implicit conversion between `Int` and `Real`. A program converts with one of five functions of the standard builtins:

| Function | Type | Result |
|---|---|---|
| `int to real n` | `Int => Real` | the `Real` nearest to n (exact when \|n\| <= 2^53) |
| `real to int x` | `Real => Int` | x without its fraction (toward zero) |
| `real round x` | `Real => Int` | the integer nearest to x; a half goes away from zero |
| `real floor x` | `Real => Int` | the greatest integer not above x |
| `real ceil x` | `Real => Int` | the least integer not below x |

The four functions that give an `Int` are total: a value above the `Int` range gives the greatest `Int`, a value below it gives the least `Int`, and a value that is not a number gives 0. None of them stops the program.

## Rationale
A `Real` could be made from an `Int` only through text, and an `Int` from a `Real` not at all. The names follow `int to str` and `str to int`. The conversion is always written, so a reader sees where precision or a fraction is lost. The functions are total because a conversion that can stop a program needs a check before every call; saturation is the choice of the IEEE-754 conversion of Rust and WebAssembly (`trunc_sat`).

## Acceptance Criteria
1. **AC-1**: `int to real 7` is `7.0`; `int to real (0 - 3)` is `-3.0`.
2. **AC-2**: `real to int 2.9` is 2 and `real to int (0.0 - 2.9)` is -2.
3. **AC-3**: `real round 2.5` is 3, `real round (0.0 - 2.5)` is -3, `real round 2.4` is 2.
4. **AC-4**: `real floor (0.0 - 2.1)` is -3 and `real ceil 2.1` is 3; a whole number is not changed by either.
5. **AC-5**: `real to int 1.0e30` is 9223372036854775807 and `real to int (0.0 - 1.0e30)` is -9223372036854775808.
6. **AC-6**: passing an `Int` where a `Real` is asked (or the reverse) is a type error.
7. **AC-7**: the results are the same on the LLVM backend, the pure x86-64 encoder and wasm32.

## Scope
The functions are builtins 136 to 140 of the IR runtime (`src/main/runtime/core/system.ll`). The Windows and macOS targets still use the old runtime blob, which does not have them (TASK-0096).
