---
id: FR-COMP-011
title: Compiler Optimization Catalog, O(N) Contiguous Tensor Allocation, In-Place Tensor Mutation, and Ephemeral SHA-256 Fusion
status: implemented
priority: must
created: 2026-10-24
updated: 2026-10-25
depends_on:
  - FR-COMP-002
  - FR-COMP-004
  - FR-COMP-010
verified_by: []
---
# FR-COMP-011 — Compiler Optimization Catalog, O(N) Contiguous Tensor Allocation, In-Place Tensor Mutation, and Ephemeral SHA-256 Fusion

## Statement
The `ridgunc` native compiler SHALL maintain a documented catalog of compile-time and codegen optimization passes (`docs/etc/compiler_optimizations.md`) and SHALL implement the following general-purpose optimizations for `Tensor[...]` operations and cryptographic/string hot loops without introducing high-level algorithm-specific built-ins:

1. **OPT-001..OPT-003 (Baseline Cataloged Passes)**:
   - **OPT-001 — Arithmetic Leaf & Tuple-Return Inlining (`RInlineExprEntry`, `RInlineTupleEntry`)**: Inline pure arithmetic leaf functions and eliminate heap tuple allocation on destructured multi-return calls (`a, b, c, d = f ...` and `v_(0), v_(1), ... = f ...`).
   - **OPT-002 — Self-Tail-Call Optimization (TCO) & Recursive Concatenation (`EBin OpConcat`) Move Lowering**: Reuse stack frames on self-tail calls (`NRebindSlot` + `NJump 0`) and move last-use local variables in recursive string/list concatenation (`RG-085`).
   - **OPT-003 — RMM1 Static Liveness & Conditional Pointer-Identity Drop (`RCmmAlias`)**: Free non-escaping heap values deterministically at static last use without runtime reference-count churn on read-only borrows.

2. **OPT-004 — $\mathcal{O}(N)$ Direct Contiguous `Tensor` Allocation (`:tensor-zeros:`)**:
   - Creating a 1D or 2D tensor (`Tensor[T * d1]` or `Tensor[T * d1 * d2]`) SHALL allocate the flat contiguous 64-bit element buffer (`data_box`) and shape vector (`shape_box`) directly in a single $\mathcal{O}(N)$ pass (`rep stosq` / `mmap` slab) rather than constructing nested Ridgun lists with `++` in $\mathcal{O}(d_1^2)$.
   - Multi-megabyte 2D tensors (e.g., `Tensor[U64 * 160000 * 16]`, ~20 MiB) SHALL initialize in `< 50 ms` without hanging or exhausting list memory.

3. **OPT-005 — Zero-Allocation `Tensor` Subscript Reads (`NIndex`), In-Place Mutation (`NIndexSet`), and Argument Mutation Preservation**:
   - Scalar element reads `m_(i)` and `m_(i, j)` on 1D/2D `Tensor`s SHALL read directly from the contiguous `data_ptr` buffer in registers without allocating temporary `slots`/`indices`/`strides` heap vectors and without atomic refcount churn on the base tensor.
   - Scalar element writes `m_(i) = val` and `m_(i, j) = val` (`NIndexSet`), row/column slice writes (`m_(r,) = v`, `m_(,c) = v`), and in-place maps (`map f in m_(i,)`, `map f in m_(,j)`, `map f in m_ij`) SHALL mutate the underlying `data_ptr` buffer in-place without cloning `data_box` or allocating a new `RVal` wrapper.
   - Mutating a `Tensor` passed as a function argument inside a helper function (including functions returning `()` or `Int`) SHALL mutate the caller's `Tensor` in-place, and statement execution order SHALL be preserved.
   - Element-wise bitwise Hadamard operations (`A_ij xor B_ij`, `A_ij and B_ij`, `A_ij or B_ij`) and column slicing (`m_(,c)`) SHALL operate directly on contiguous `Tensor` buffers without intermediate $\mathcal{O}(N^2)$ list concatenations.

4. **OPT-006 — Zero-Allocation `sha256_raw` Direct Digest & Ephemeral Concatenation Fusion (`sha256_raw (a + b)`)**:
   - `sha256_raw` (`NCallBuiltin 36`) SHALL write the 32 big-endian digest bytes directly into a 32-byte `String` without intermediate ASCII hex formatting (`core::fmt::write`) or hex-to-byte parsing, and without heap-allocating a padded copy of the input when hashing in blocks.
   - When `sha256_raw` is applied to a string concatenation expression `sha256_raw (a + b)` (the canonical HMAC/PBKDF2 pattern `sha256 raw (opad + (sha256 raw (ipad + u)))`), the compiler SHALL fuse the operation (`NCallBuiltin 89`) to hash the byte slices of `a` and `b` sequentially (caching the 64-byte first-block midstate when `len(a) == 64`) without allocating or freeing the temporary concatenated string `a + b` on the heap.

## Rationale
- High-performance library code in pure Ridgun (`crypto.rg`, `argon2id.rg`, numerical/scientific computing) must achieve sub-second throughput through legitimate compiler and runtime codegen optimizations rather than by embedding library algorithms (`pbkdf2`, `argon2id`) as compiler built-ins.
- Documenting every compiler optimization pass with a stable identifier (`OPT-001`..`OPT-006`) establishes a dedicated optimization architecture area in `ridgunc` that can grow systematically.

## Acceptance Criteria
1. **AC-1 (Optimization Catalog)**: `docs/etc/compiler_optimizations.md` documents `OPT-001` through `OPT-006` with AST/IR patterns, preconditions, and cost models, and is indexed in `docs/etc/INDEX.md`.
2. **AC-2 ($\mathcal{O}(N)$ Large Tensor Allocation & In-Place Argument Mutation)**: Allocating `Tensor[U64 * 160000 * 16]` (~20 MiB) and mutating a `Tensor` inside a function returning `()` or `Int` succeed in `< 50 ms` and preserve mutations in the caller.
3. **AC-3 (Cryptographic Hot-Loop Throughput in Pure Ridgun)**: 600,000 iterations of `sha256 raw (opad + (sha256 raw (ipad + u)))` (PBKDF2-HMAC-SHA256 core) and Argon2id / BlaMka tensor block compression execute in `< 1 s` in pure Ridgun.
