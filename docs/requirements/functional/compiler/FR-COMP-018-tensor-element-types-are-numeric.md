---
id: FR-COMP-018
title: Tensor Element Types Are Numeric
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-07
updated: 2026-11-07
depends_on:
  - FR-COMP-016
verified_by: [TS-COMP-018]
---
# FR-COMP-018 — Tensor Element Types Are Numeric

> Since 0.9.37 (`FR-COMP-020`), only `Tensor_GPU` keeps this rule. `Tensor` accepts any element type.

## Statement
1. **Numeric element types.** A tensor stores one 64-bit number per element. The element type of a tensor, written as `Tensor[T * n ...]`, `Tensor[T]` or `Tensor(T, n ...)` in a type or in an allocation expression, SHALL be one of `Int`, `Byte`, `U8`, `U16`, `U32`, `U64`, `I8`, `I16`, `I32`, `I64`, `Usize`, `Real` or `Float`. The same rule applies to `Tensor_GPU`.
2. **Compile error.** For `Tensor_GPU`, any other element type (for example `String`, `Bool`, `Char`, a list or a user-defined type) SHALL be a compile error: `syntax error: Tensor_GPU element type '<T>' is not supported: a Tensor_GPU holds numbers only (Int, Byte, U8, U16, U32, U64, I8, I16, I32, I64, Usize, Real, Float) in function '<name>'`. (Before 0.9.37 the rule also applied to `Tensor`.)

## Rationale
Before 0.9.35 the compiler ignored the element type. `Tensor[String * 3]` compiled, `t_(1) = "hola"` stored nothing and `t_(1)` returned `0`, without any error. `Tensor[Bool * n]` lost `True` the same way. Found while reviewing the ridgun-libs request for an `Array A` type (2026-11-07).

## Acceptance Criteria
1. **AC-1**: `Tensor_GPU[String * 3]` in an expression fails to build with the message of §2 (`tests/cases/tensors/tensor_gpu_of_string_fails.rg`).
2. **AC-2**: `Tensor_GPU[Bool * n]` in a parameter type fails to build, and the message names the function (`tests/cases/tensors/tensor_gpu_of_bool_in_signature_fails.rg`).
3. **AC-3**: `Int`, `U64`, `Byte` and `Real` tensors still build, and integer tensors keep the values written to them (`tests/cases/tensors/numeric_tensor_elements_still_build.rg`).
