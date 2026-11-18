---
id: FR-COMP-030
title: Every operator has a defined result for every pair of types
status: implemented
priority: must
created: 2026-11-18
updated: 2026-11-18
depends_on:
  - FR-COMP-027
related: []
verified_by: []
---
# FR-COMP-030 — Every operator has a defined result for every pair of types

## Statement
1. **No undefined combination.** For each binary operator (`+ - * / %`, `== != < > <= >=`, `and or xor`, `shl shr rotl rotr`) and each pair of operand kinds (`Int`, `Real`, integer tensor, `Real` tensor, whole or by element), the program either builds and gives the value this document states, or does not build and the compiler says why. A combination never gives a runtime error, an empty tensor or an unrelated number.
2. **`Real` follows IEEE 754 binary64.**
   - A comparison with NaN is false; `!=` with NaN is true. So `x != x` is the test for NaN.
   - `+inf` and `-inf` order as the largest and the smallest value; `0.0 == -0.0`.
   - `1.0 / 0.0` is `inf`, `0.0 / 0.0` is NaN, `inf - inf` is NaN.
   - The text of the special values is `inf`, `-inf`, `nan`, `-0.0`.
   - The conversions of FR-COMP-027 give 0 for NaN and saturate for the infinities.
3. **Operators on integers only.** `shl`, `shr`, `rotl`, `rotr` with a `Real` operand do not build: `operator <op> needs Int operands`.
4. **Element-wise form.** `a_ij <op> b_ij` in a function whose parameters are tensors gives a tensor with `<op>` applied to each pair of elements:
   - integer tensors: `xor and or shl shr rotl rotr + - * / %`. `shl` and `shr` use the count modulo 64 and `shr` is logical. `/` and `%` by zero give 0.
   - `Real` tensors: `+ - * /`, with the rule of point 2.
   - `%` and the bit, shift and rotate operators on a `Real` tensor, and `+ - * /` between an integer tensor and a `Real` tensor, do not build.
5. **Whole tensors.** An arithmetic or bit operator between two tensors without subscripts does not build: `operator <op> between two tensors needs subscripts, as in a_ij <op> b_ij`.
6. **One loop per operator.** The element-wise form of every operator of point 4 is one loop over the raw words of the two tensors in the runtime (builtin 90), which the back end can vectorise; `shl` and `shr` cost the same per element as `xor`.

## Rationale
Until 1.0.35 only some combinations had a test, each written by hand when a defect was reported. A table of 283 rows built on 2026-11-18 showed 92 combinations that were wrong: a comparison with NaN went through a three-way order and gave true for `==`, `<=` and `>=`; `shl` and `shr` between tensors ran element by element through the scalar path; `/` between tensors gave an empty tensor; `%` and the rotations stopped at run time; arithmetic on `Real` tensors added the bit patterns as integers; infinity was printed as a saturated number. A rule for the whole table, checked by a generated test, replaces the cases one at a time.

## Acceptance Criteria
1. **AC-1**: with `nan = inf - inf`, the six comparisons of `nan` with `0.0`, with `nan` and with `inf`, in both orders, give `F T F F F F` (only `!=` is true).
2. **AC-2**: `inf == inf`, `inf > -inf`, `0.0 == -0.0`, `1.0 / 0.0 == inf` are true; `0.0 / 0.0` and `inf * 0.0` are NaN.
3. **AC-3**: `echo` of `inf`, `-inf`, NaN and `-0.0` prints `inf -inf nan -0.0`; `real to int` of them gives `9223372036854775807`, `-9223372036854775808`, `0`, `0`.
4. **AC-4**: for `U64` tensors `[3, 1, 1, 255, -1]` and `[4, 63, 64, 0, 1]`, `shl` gives `48 -9223372036854775808 1 255 -2`, `shr` gives `0 0 1 255 9223372036854775807`, `/` gives `0 0 0 0 -1`, `%` gives `3 1 1 0 0`.
5. **AC-5**: for `Real` tensors `[7.5, 1.5]` and `[2.0, 0.5]`, `+ - * /` give `9.5 2.0`, `5.5 1.0`, `15.0 0.75`, `3.75 3.0`.
6. **AC-6**: every row of the table in `src/test/ridgun/test operator matrix.ridgun` holds with the LLVM back end and with the pure x86-64 encoder.
7. **AC-7**: the WebAssembly back end gives the same output for AC-1 to AC-5.

## Not in scope
- A finite `Real` of 2^64 or more is still printed saturated.
- `Real` to and from its bits, the shortest text that reads back to the same value, and reading a `Real` from text.
- Operators between a scalar and a tensor.
