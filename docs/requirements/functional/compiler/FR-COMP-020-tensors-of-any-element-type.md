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
   - The syntax is `Tensor[T * dims] with v`, for example `Tensor[Visit * 10] with Visit "ana" 1` or `Tensor[Char * 8 * 8] with '.'`. `v` SHALL have type `T`.
   - An allocation without an initial value SHALL be allowed only for element types with a default value: `0` for numbers, the character of code 0 for `Char`, `""` for `String`, `False` for `Bool`, `[]` for lists. For tuples, records and ADTs it SHALL be a compile error.
7. **Numeric-only operations.** `@` (einsum), element-wise arithmetic and matrix products SHALL be a compile error when an operand has non-numeric elements. `Tensor_GPU` SHALL keep numeric elements only (the FR-COMP-018 error stays for it).
8. **Index out of range.** On every tensor, numeric or not, a read or write with an index outside the shape (`i < 0` or `i >= d`) SHALL stop the program with `runtime error: tensor index out of range` (stderr, exit status 1), as FR-COMP-017 does for a call that matches no clause. It SHALL NOT return a zero value or write outside the tensor. A negative index is out of range; it does not count from the end. This covers element access (`t_(i ...)`, also with fewer indices than the rank) and row and column slices (`m_(r,)`, `m_(,c)` and their writes). Decided by the user (2026-11-07).
9. **Lists.** `tensor from list xs` (one dimension, any element type) and `tensor to list t` SHALL be native operations, without a per-element cost in Ridgun code.
10. **Showing and comparing.** `echo` and `==` on a tensor of non-numeric elements SHALL show and compare elements by their type. `echo` and string interpolation SHALL show a numeric tensor's elements by their type too (`data=[1, 2]` for `Int`, `data=[1.5, 2.5]` for `Real`). A tensor literal of `Real`s SHALL keep its values and have type `Tensor[Real]`; a literal mixing `Int` and `Real` SHALL be a compile error.
11. **Parallel writes.** `|| ... -> out[i]` into a tensor of non-numeric elements SHALL be a compile error until a safe rule is defined (two parallel tasks can change the reference count of the same value).
13. **Sending tensors.** A tensor sent to an agent (`send`, `ask`), sent through a channel (`send ... through`) or given as an agent's initial state SHALL be a copy: the receiver never gets the sender's tensor, so a write on one side never reaches the other. This holds for a tensor variable, a function result and a tuple of them. A message whose tensor is inside a list, an ADT or a record SHALL be a compile error until such values can be copied. Ridgun has no shared type (`shared ::` was removed by FR-COMP-009). Decided by the user (2026-11-07).
12. **Backends.** Every requirement SHALL hold on LLVM, the pure x86-64 encoder and the ARM64 encoder (ELF64, Mach-O 64, PE32+).

## Phases
1. Element typing in the type checker (§2). It also fixes `Real` tensor elements.
2. GenTensor storage with RMM (§1, §3-§6, §8, §10), on every backend.
3. Native list conversion (§9).
4. Compile errors for numeric-only operations, `Tensor_GPU` and parallel writes (§7, §11).
5. Bounds errors on numeric tensors (§8) and copies on send (§13).

## Implementation status (0.9.45)
- Done on LLVM and the pure x86-64 encoder: the Statement (including shape patterns) and §1-§11, §13 (phases 1-5).
- Every `tests/cases/tensors` case gives the same output and exit status on LLVM and on the pure x86-64 encoder (`--target x86_64-elf`).
- §12: the ARM64 encoder emits placeholders for the GenTensor instructions. Its runtime has no `Real` or GenTensor support yet.
- Representation: a GenTensor is not a separate heap tag. A one-dimensional GenTensor is an RC vector of boxed elements (the list representation, tag `2`); a two-dimensional one is a vector of row vectors. The type checker keeps numeric-only code away from it (§7). Details: `docs/etc/gentensor.md`.
- A GenTensor has one or two dimensions; a third dimension is a compile error.
- Initial value (§6): `Tensor[T * dims] with v`, on numeric tensors of any rank and on GenTensors of one or two dimensions.
- 0.9.45 (libs report 2026-11-08):
  - A tensor made by a generic function (`Tensor[V * n] with v`) is a GenTensor even when `V` is `Int` or `Real`. Writes through a `Tensor[Int]` or `Tensor[Real]` parameter now check for it at run time, like reads. Only programs that create such a tensor pay for the check.
  - Creating a GenTensor of n elements is one allocation and n clones (`NGtConv` mode 5), not n list appends: 1,000,000 `String` elements in about 20 ms instead of 790 ms.
  - `@` on `Tensor[Real]` operands computes with `Real`s (loops; on LLVM a native path for two rank-2 operands). Before, it multiplied the f64 bits as integers and gave zeros.
  - Known gap: a generic function that reads a numeric `Tensor[Real]` (made with `Tensor[Real * n]`, not generically) gets the f64 bits as an `Int`, because a numeric tensor does not record its element type at run time.

## Open questions
- Copying a tensor inside a list, an ADT or a record on send (today a compile error, §13).
- Replies: a stateful agent that replies with a tensor from its own state gives the caller that tensor, not a copy.

## Rationale
An indexed collection of any type with constant-time access is a basic building block: memo tables, caches and hash maps with any value type, lookup tables, graph adjacency lists. Lists give linear-time access, and tensors held only numbers. The ridgun-libs team asked for this as a separate `Array A` type (2026-11-07). Ridgun provides it as `Tensor` instead, with one name and one syntax for every element type.

## Out of scope
- Sparse tensors (FR-COMP-019).
- `Tensor_GPU` with non-numeric elements.
