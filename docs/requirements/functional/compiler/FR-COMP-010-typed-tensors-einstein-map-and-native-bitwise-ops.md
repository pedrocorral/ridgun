---
id: FR-COMP-010
title: First-Class Typed Tensors (`Tensor[...]`), Subscript Views & Mapping (`map f in m_(i,)`), and Native Bitwise Operations
status: implemented
priority: must
created: 2026-10-23
updated: 2026-10-23
depends_on:
  - FR-COMP-001
  - FR-COMP-002
  - FR-COMP-004
verified_by: []
---
# FR-COMP-010 — First-Class Typed Tensors (`Tensor[...]`), Subscript Views & Mapping (`map f in m_(i,)`), and Native Bitwise Operations

## Statement
The Ridgun language and `ridgunc` / `stable` toolchain SHALL provide first-class typed contiguous `Tensor`s, unified subscript (`_`) notation for indexing, zero-copy slicing, Hadamard operations, and axis-aware `map` / `||map` (including in-place `map f in m` / `||map f in m`), and native 1-cycle CPU bitwise operations:

1. **First-Class Typed `Tensor[...]` Signatures, Creation & Pattern Matching**:
   - Type signatures, constructors, and `fn ::` / `op ::` pattern matching SHALL support glued bracket `Tensor[...]` specifications:
     - `Tensor[T]` — tensor of element type `T` (`Byte`, `U8`, `U32`, `U64`, `Int`, `Real`) of arbitrary rank.
     - `Tensor[T^k]` — tensor of element type `T` of rank `k` with unspecified dimensions (e.g., `Tensor[Byte^4]`).
     - `Tensor[T * d1 * d2 * ... * dk]` — tensor with concrete dimensions (`> 0`), free/wildcard dimensions (`0` or `_`), or bound dimension variables (`f`, `c`) in `fn ::` / `op ::` parameter patterns, e.g. `(Tensor[U64 * 16] v)` or `(Tensor[Byte * f * c] m)`.
   - Contiguous 64-bit integer/byte element storage (`Int`, `U64`, `U32`, `Byte`/`U8`) SHALL preserve full 64-bit precision without lossy `f64` conversion.

2. **Unified Subscript (`_`) Indexing, Slicing & Views**:
   - Subscript notation `m_(i)`, `m_(i, j)`, `m_ij` SHALL read or update (`m_(ia) = expr` with `RMM2` in-place mutation when `refcount == 1` or on an `in` view) elements of a tensor.
   - Partial subscripts `m_(r,)` (row `r` view) and `m_(,c)` (column `c` strided view) and range slices `m_(r1..r2, c1..c2)` SHALL produce lightweight tensor views (`Tensor`) referencing the underlying buffer with base offset and strides (zero heap copy when read or mutated via `in`).

3. **Axis-Aware `map` / `||map` and In-Place `map f in m` / `||map f in m`**:
   - `map f m_ij` and `map f in m_ij` SHALL apply `f` to every scalar element of `m`.
   - `map f m_(i,)` / `||map f m_(i,)` and `map f in m_(i,)` / `||map f in m_(i,)` SHALL iterate along axis `i` (optionally bounded via `m_(i=a..b,)`), passing each 1D row slice `Tensor[T * cols]` to `f`.
   - `map f m_(,j)` / `||map f m_(,j)` and `map f in m_(,j)` / `||map f in m_(,j)` SHALL iterate along column axis `j`, passing each 1D column slice `Tensor[T * rows]` to `f` and writing back in-place when `in` is specified.

4. **Native 1-Cycle CPU Bitwise Operations on Scalars and Tensors**:
   - Binary operators `xor`, `and`, `or`, `shl`, `shr`, `rotr`, `rotl` and unary `not` SHALL compile directly to native CPU bitwise instructions on integer scalars (`Int`, `U64`, `U32`, `Byte`) and element-wise Hadamard operations on subscripted tensors (`A_ij xor B_ij`, `A_ij and B_ij`, `A_ij or B_ij`).

## Rationale
- Cryptographic and numerical workloads (Argon2id, Blake2b, PBKDF2-HMAC-SHA256, ChaCha20) require 1-cycle CPU bitwise instructions and cache-local in-place transformations over contiguous 64-bit word blocks (`Tensor[U64 * 8 * 16]`) without degrading Ridgun into a pointer-oriented systems language.
- Extending the existing Einstein `_` subscript notation (`A_ik @ B_kj`, `A_ij + B_ij`) to views (`m_(3,)`, `m_(,5)`), cell updates (`v_(ia) = ...`), and `map f in m_(i,)` / `map f in m_(,j)` keeps the language 100% declarative and mathematically uniform.

## Acceptance Criteria
1. **AC-1 (`Tensor[...]` Type, Creation & Pattern Matching)**: `Tensor[Byte]`, `Tensor[Byte^4]`, `Tensor[U64 * 16]`, `Tensor[U64 * 8 * 16]`, and dimension-binding patterns `(Tensor[U64 * r * c] m)` parse, typecheck, format, and execute in `fn ::` and `op ::`.
2. **AC-2 (Native 64-Bit Bitwise Operations)**: `xor`, `and`, `or`, `not`, `shl`, `shr`, `rotr`, `rotl` execute in 1-cycle native instructions on 64-bit integers and element-wise on tensors (`x_ij xor y_ij`).
3. **AC-3 (Subscript Indexing, Views & `map f in m_(i,)` / `map f in m_(,j)`)**: `v_(ia) = ...` mutates in-place under RMM2, `m_(r,)` and `m_(,c)` extract row/column views, and `map f in m_(i,)` / `map f in m_(,j)` (and `||map f in m_(i,)`) transform rows and columns in-place (verified by a full BlaMka `blamka g` / `blamka p16` block compression test on `Tensor[U64 * 8 * 16]`).
