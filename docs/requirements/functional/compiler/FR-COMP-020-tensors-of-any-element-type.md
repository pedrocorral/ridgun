---
id: FR-COMP-020
title: Tensors of Any Element Type
type: functional
domain: compiler
status: approved
priority: must
created: 2026-11-07
updated: 2026-11-07
depends_on:
  - FR-COMP-018
related: [FR-COMP-019]
verified_by: [TS-COMP-020]
---
# FR-COMP-020 — Tensors of Any Element Type

## Statement
`Tensor` SHALL accept any element type, not only numbers: `String`, `Bool`, `Char`, lists, tuples, records and ADTs. A tensor of non-numeric elements SHALL use the same syntax as a numeric tensor (shape, `t_(i)` reads and writes, shape patterns). Internally it is a separate kind of tensor (called *GenTensor* in the compiler), so numeric tensors keep their current representation and speed.

## Decisions
- **One name.** Every tensor is called `Tensor` in the language, whatever its element type. Precedent: TensorFlow tensors with `tf.string` elements.
- **The element type is part of the type**, next to the shape, and the compiler knows it at compile time. Reading `t_(i)` from a `Tensor[String * n]` gives a `String`.
- **GenTensor inside.** A tensor of non-numeric elements has its own heap tag. Code for numeric tensors (einsum fast paths, matrix product, row and column helpers) never sees one.

## Requirements
1. **Element types.** `Tensor[T * n ...]`, `Tensor[T]` and `Tensor(T, n ...)` SHALL accept any type `T` in types and in allocation expressions. This replaces the compile error of FR-COMP-018 §2 for `Tensor`.
2. **Element typing.** The type checker SHALL give `t_(i ...)` the element type of `t`, for every tensor including numeric ones. A `Real` tensor element is a `Real`: `echo t_(1)` prints the number and `t_(1) + 1.0` type-checks. Before this requirement every element was typed `Int`, so a `Real` element printed its raw 64-bit pattern.
3. **Reads and writes.** `t_(i ...)` reads and `t_(i ...) = v` writes an element in constant time, in place, as for numeric tensors today.
4. **Passing by reference.** Passing a tensor to a function or returning it SHALL NOT copy it, as for numeric tensors today.
5. **Memory (RMM).** Writing an element SHALL add one reference to the new value and drop one from the old value. Freeing a tensor SHALL drop one reference from every element. Cloning a tensor SHALL add one reference to every element.
6. **Initial values.**
   - An allocation SHALL be able to give an initial value for every element type (for example a `Visit` value repeated `n` times).
   - An allocation without an initial value SHALL be allowed only for element types with a default value: `0` for numbers, `""` for `String`, `False` for `Bool`, `[]` for lists. For other types it SHALL be a compile error.
7. **Numeric-only operations.** `@` (einsum), element-wise arithmetic and matrix products SHALL be a compile error when an operand has non-numeric elements. `Tensor_GPU` SHALL keep numeric elements only (the FR-COMP-018 error stays for it).
8. **Index out of range.** On a tensor of non-numeric elements, a read or write outside the shape SHALL stop the program with a runtime error (stderr, exit status 1), as FR-COMP-017 does for a call that matches no clause. It SHALL NOT return a zero value.
9. **Lists.** `tensor from list xs` (one dimension, any element type) and `tensor to list t` SHALL be native operations, without a per-element cost in Ridgun code.
10. **Showing and comparing.** `echo` and `==` on a tensor of non-numeric elements SHALL show and compare elements by their type.
11. **Parallel writes.** `|| ... -> out[i]` into a tensor of non-numeric elements SHALL be a compile error until a safe rule is defined (two parallel tasks can change the reference count of the same value).
12. **Backends.** Every requirement SHALL hold on LLVM, the pure x86-64 encoder and the ARM64 encoder (ELF64, Mach-O 64, PE32+).

## Phases
1. Element typing in the type checker (§2). It also fixes `Real` tensor elements.
2. GenTensor storage with RMM (§1, §3-§6, §8, §10), on every backend.
3. Native list conversion (§9).
4. Compile errors for numeric-only operations, `Tensor_GPU` and parallel writes (§7, §11).

## Implementation status (0.9.37)
- Done on LLVM and the pure x86-64 encoder: §1-§11 (phases 1-4), except shape patterns on tensors of non-numeric elements.
- §12: the ARM64 encoder emits placeholders for the GenTensor instructions. Its runtime has no `Real` or GenTensor support yet.
- Representation: a GenTensor is not a separate heap tag. A one-dimensional GenTensor is an RC vector of boxed elements (the list representation, tag `2`); a two-dimensional one is a vector of row vectors. The type checker keeps numeric-only code away from it (§7). Details: `docs/etc/gentensor.md`.
- A GenTensor has one or two dimensions; a third dimension is a compile error.
- Initial value (§6): implemented as `tensor fill v n` and `tensor fill v r c`. The name is provisional until the open question below is closed.

## Open questions
- The syntax for an allocation with an initial value (§6). Provisional: `tensor fill v n`, `tensor fill v r c`.
- Whether bounds checks (§8) also apply to numeric tensors, and at what cost.
- What happens when a tensor of non-numeric elements is sent to another agent: copy it, or a compile error.

## Rationale
An indexed collection of any type with constant-time access is a basic building block: memo tables, caches and hash maps with any value type, lookup tables, graph adjacency lists. Lists give linear-time access, and tensors held only numbers. The ridgun-libs team asked for this as a separate `Array A` type (2026-11-07). Ridgun provides it as `Tensor` instead, with one name and one syntax for every element type.

## Out of scope
- Sparse tensors (FR-COMP-019).
- `Tensor_GPU` with non-numeric elements.
