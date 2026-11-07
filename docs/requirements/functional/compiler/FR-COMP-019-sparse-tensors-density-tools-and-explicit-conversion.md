---
id: FR-COMP-019
title: Sparse Tensors, Density Tools and Explicit Conversion
type: functional
domain: compiler
status: draft
priority: must
created: 2026-11-07
updated: 2026-11-07
depends_on:
  - FR-COMP-018
related: []
verified_by: []
---
# FR-COMP-019 — Sparse Tensors, Density Tools and Explicit Conversion

## Statement
Ridgun SHALL offer sparse tensors as a storage form of `Tensor` that is fixed at compile time. It SHALL give the programmer tools to measure a tensor's density, to judge whether the dense or the sparse form is faster, and to convert between the two. A conversion SHALL only happen when the program calls it; Ridgun SHALL NOT convert a tensor on its own (see "Deferred").

## Concepts
- **Dense tensor:** stores every position. This is today's `Tensor`.
- **Sparse tensor:** stores only the positions whose value is not the default value (`0` for numbers), each with its indices.
- **Storage is part of the type.** The compiler knows at compile time whether a tensor is dense or sparse and generates the code for that form. A dense tensor and a sparse tensor are different types.
- **Density:** stored elements divided by the total number of positions (the product of the dimensions).
- **Threshold:** the density above which the dense form of an operation is faster than the sparse form. It depends on the operation (`@`, `+`, `map`, ...) and on the machine.

## Tools
1. **Size and stored elements.** `tensor size t` returns the number of positions. `tensor stored t` returns the number of stored elements. For a dense tensor, `tensor stored t` equals `tensor size t`. Both SHALL take constant time.
2. **Density.** `tensor density t` returns `tensor stored t / tensor size t` as a `Real`, in constant time.
3. **Threshold.** `sparse threshold op` returns the measured threshold of operation `op` on the machine that runs the program.
4. **Evaluation.** `worth sparse t op` returns `True` when `tensor density t` is below `sparse threshold op`.
5. **Conversion.** `to dense t` returns a dense tensor with the same shape and values. `to sparse t` returns a sparse tensor that stores only the non-default values. Each conversion visits every position once.
6. **Compile-time warnings.** When an operation on a sparse tensor gives a mostly non-default result (for example `exp`, or adding a non-zero constant), the compiler SHALL print a warning that names the function and the operation and says that the result is dense. A warning SHALL NOT stop the build.
7. **Diagnostic mode.** In a diagnostic build, when a sparse tensor enters an operation with a density above that operation's threshold, the program SHALL report it once per variable, with the function, the variable, the density and the threshold. Outside diagnostic builds this check SHALL cost nothing.

## Acceptance Criteria
1. **AC-1:** For a sparse tensor of shape `100 × 100` with 50 stored values, `tensor size` is `10000`, `tensor stored` is `50` and `tensor density` is `0.005`.
2. **AC-2:** `to dense (to sparse t)` equals `t` for any dense numeric tensor `t`, and `to sparse` stores exactly the non-zero values.
3. **AC-3:** `worth sparse t op` agrees with `tensor density t < sparse threshold op`.
4. **AC-4:** `exp` applied to a sparse tensor builds with a warning that names the function; the build succeeds.
5. **AC-5:** A diagnostic build reports a sparse tensor above its threshold once; a normal build of the same program prints nothing extra.

## Constraints & edge cases
- A sparse tensor that fills up stays sparse until the program converts it.
- Converting costs one visit per position, so a program should convert at a point it chooses, not inside a hot loop.
- An empty tensor (size `0`) has density `0`.

## Open questions (to decide before implementation)
- The syntax that marks a tensor type as sparse.
- Which sparse formats to support (COO for building, CSR/CSC for fast products, or others).
- How thresholds are measured and stored for each machine (for example, measured once when Ridgun is installed).
- The flag that turns on the diagnostic mode.
- How sparse tensors combine with tensors of non-numeric elements, where the default value is not `0` (for example `""` for `String`).

## Deferred: automatic conversion (not part of this requirement)
Recorded for a future requirement. Not to be implemented now.
- The programmer marks a tensor as adaptive, and the compiler generates both the sparse and the dense version of the code that uses it.
- After each operation that can change the tensor's density, the program checks the density and converts when it crosses a threshold.
- Two thresholds avoid switching back and forth: for example, switch to dense above 10 % and back to sparse below 2 %.
- A conversion visits every position, so it happens only when a threshold is crossed.

## Rationale
Many tensors are mostly zeros: graph adjacency matrices, documents × words, users × products, finite-element systems, visitors × routes. A sparse form saves memory and time in proportion to the stored values. It is slower than the dense form once density grows, and that point depends on the operation and the machine, so the programmer needs to measure it and decide.

## Out of scope
- Automatic conversion (see "Deferred").
- Sparse tensors on the GPU (`Tensor_GPU`).
