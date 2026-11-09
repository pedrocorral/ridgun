---
id: FR-COMP-011
title: Compiler Optimization Catalog, O(N) Contiguous Tensor Allocation, In-Place Tensor Mutation, and Ephemeral SHA-256 Fusion
status: implemented
priority: must
created: 2026-10-24
updated: 2026-11-09
depends_on:
  - FR-COMP-002
  - FR-COMP-004
  - FR-COMP-010
verified_by: [TS-COMP-011]
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

5. **OPT-008 — Inline LLVM IR Register Fast-Paths (`NBinOp`, Slot Operations, 64-Bit `U64` Heap Boxing, and `str_char_at`)**:
   - The LLVM IR backend (`llvm.rg`) SHALL execute arithmetic, comparison, and bitwise operations (`+`, `-`, `*`, `/`, `%`, `==`, `!=`, `>`, `<`, `>=`, `<=`, `and`, `or`, `xor`, `shl`, `shr`, `rotr`, `rotl`) and slot/boolean operations (`NCloneSlot`, `NStoreSlot`, `NRebindSlot`, `NCmmDropSlot`, `NDropVal`, `NAsBool`) directly in LLVM IR via `opt -O2` + `llc -O2` without calling external `.rt` helpers on immediate `Int`/`Bool` values.
   - `@__rg_box_i64` SHALL preserve all 64 bits of unsigned/signed 64-bit integers (`U64`) when `bit 63 != bit 62` (`0x4000000000000000 .. 0xBFFFFFFFFFFFFFFF`) by storing the 64-bit integer heap tag `-9223372036854775808` (`0x8000000000000000`) at offset 0 of the `RVal` buffer, and `NBinOp` / `NNot` / `Tensor` indexing SHALL unbox and operate on full 64-bit `U64` values transparently.
   - `str_char_at` (`NCallBuiltin 40` and `NCallBuiltin 91` for local string variables) SHALL read the unsigned byte directly from the string's `dptr` buffer in LLVM IR without cloning or dropping the `String` when borrowing a local variable.

6. **OPT-009..OPT-014 — Unrolled Frame SROA, `!invariant.load` Tensor Metadata CSE/LICM, Zero-Boxing Row/Col Slice & Set Built-ins (`92..95`), SIMD-Vectorized Flat Hadamard & 2D `NEinsum`, Direct Register Calling Convention (`@__rg_fn_{fid}_reg`), and HOF Direct-Call Specialization**:
   - **OPT-009 — Unrolled Constant-Offset Frame Prologue/Epilogue & Direct `NCallFn` in `Tensor` Maps**: Unrolls function prologue (`0..arity-1` from `%args`, `arity..num_slots-1` zeroed), `NClearLocals`, and function epilogue (`epilogue_exit:`) into constant-offset `getelementptr` + `@__rg_fast_drop_val` for non-TCO functions (`fid >= 5`, `num_slots <= 24`), passes `i64` values by value to `@__rg_tensor_index_*_slow` so `%frame` pointers never escape, and emits direct `NCallFn` instead of `NCallIndirect1` in `map f m_(i,)` / `map f in m_(i,)` / `map f in m_(,j)` / `map f in m_ij` when `f` is a top-level unary function.
   - **OPT-010 — `!invariant.load !0` on Immutable `Tensor` Metadata**: Marks all `Tensor` `tag`, `shdr`, `dhdr`, `sptr`, `rk`, `d0`, `d1`, `dptr`, and `len` loads in `llvm.rg` with `!invariant.load !0`, and marks `@__rg_rt_alloc_buf` and `@__rg_rt_box_rc_vec` return pointers `noalias` so `opt -O2` (`EarlyCSE` / `GVN` / `LICM`) hoists all pointer indirections and bounds checks out of loops and multi-index functions.
   - **OPT-011 — Hardware `rep movsb`/`rep stosb`/`rep stosq` & Zero-Boxing Row/Col Slice & Set (`NCallBuiltin 92..95`)**: Inlines hardware `rep movsb` / `rep stosb` in `@__rg_memcpy` / `@__rg_memset` and `rep stosq` in `@__rg_builtin_tensor_fill`, and lowers `m_(r,)` (`92`), `m_(r,) = v` (`93`), `m_(,c)` (`94`), and `m_(,c) = v` (`95`) to unboxed `i64` memory/strided copies with zero per-element boxing/unboxing.
   - **OPT-012 — SIMD-Vectorized Flat Hadamard (`+`, `-`, `*`, `and`, `or`, `xor`) & Cache-Friendly 2D `NEinsum` (`@__rg_fast_einsum`)**: Hoists `switch i64 %op_id` outside the loop in `@__rg_builtin_tensor_bitop` (`NCallBuiltin 90`) into 6 branch-free vectorizable loops (`+`, `-`, `*`, `and`, `or`, `xor`) and executes 2D matrix multiplication (`A_ik @ B_kj` / `A_ij @ B_jk`) in a unit-stride `i-k-j` loop in `@__rg_fast_einsum`.
   - **OPT-013 — Direct SSA Register Calling Convention (`@__rg_fn_{fid}_reg`) & Caller Frame Escape Elimination**: Emits a register-parameter entry `@__rg_fn_{fid}_reg(i64 %arg_0, ...)` for user functions (`fid >= 5`, `arity <= 8`) alongside the indirect ABI wrapper `@__rg_fn_{fid}(ptr %args)`, and lowers direct `NCallFn` instructions to load arguments from `%frame`, zero the caller argument slots (`store i64 0`), and call `@__rg_fn_{fid}_reg` directly in hardware registers so caller `%frame` pointers do not escape across calls.
   - **OPT-014 — AST-Level Higher-Order Function (`fold`, `map`, `filter`) Direct-Call Specialization**: Specializes `fold f init xs`, `map f xs`, and `filter p xs` when `f`/`p` is a known top-level function or non-capturing lambda into direct-call recursive helpers (`__rg_spec_fold_*`, `__rg_spec_map_*`, `__rg_spec_filter_*`) that leverage self-TCO (`OPT-002`) and direct register calls (`OPT-013`) instead of indirect runtime dispatch (`NCallIndirect1` / `NCallIndirect2`).

7. **OPT-015..OPT-018 — Cheap Loops, Field Reads and Small Calls (TASK-0059)**:
   - **OPT-015**: On LLVM, a function with a self tail call and at most 24 slots SHALL copy the tail-call arguments, drop its slots and return without calling the runtime (`@__rg_rt_tco_copy`, `@__rg_rt_epilogue`), so its frame stays in registers.
   - **OPT-016**: A record field read `field r` SHALL read the field from the record without calling the accessor; when `r` is a local variable the record SHALL NOT be cloned or dropped. On LLVM, field reads and constructor matches on ADTs SHALL run inline, with the runtime call kept only for values that are not ADTs or fields out of range.
   - **OPT-017**: In a self tail call, a parameter passed as an argument and read by a later argument SHALL be moved, not cloned.
   - **OPT-018**: A parameter that every clause of a function only matches with a pattern (constructor, tuple, `[]`, string or `_`) SHALL be borrowed: the caller passes a local variable without a clone and the callee does not drop it. This applies only to functions that are called directly (not used as values, partially applied, dispatched by name, agents, entry points or library exports) and do not call themselves.
   - These optimizations SHALL NOT change any program output, exit status or `cmm live blocks` result.
8. **OPT-019 — Tail Calls Between Different Functions (TASK-0061)**:
   - A direct call to another function in tail position SHALL compute its arguments, drop the caller's remaining values, release the caller's frame and then transfer control to the callee, which returns straight to the caller's caller (`NTailCallFn`). No work SHALL follow the call ("Rule: tail calls stay last" in `docs/etc/compiler_optimizations.md`).
   - On LLVM the register entry points `@__rg_fn_{fid}_reg` use the `tailcc` calling convention, so a `tail call` in tail position is always a jump; the targets of such calls have `weak_odr` linkage so the optimizer cannot replace the call's result by a constant and lose the tail position.
   - The limits per backend are listed in FR-COMP-004 §3.

## Rationale
- High-performance library code in pure Ridgun (`crypto.rg`, `argon2id.rg`, numerical/scientific computing) must achieve sub-second throughput through legitimate compiler and runtime codegen optimizations rather than by embedding library algorithms (`pbkdf2`, `argon2id`) as compiler built-ins.
- Documenting every compiler optimization pass with a stable identifier (`OPT-001`..`OPT-006`) establishes a dedicated optimization architecture area in `ridgunc` that can grow systematically.

## Acceptance Criteria
1. **AC-1 (Optimization Catalog)**: `docs/etc/compiler_optimizations.md` documents `OPT-001` through `OPT-006` with AST/IR patterns, preconditions, and cost models, and is indexed in `docs/etc/INDEX.md`.
2. **AC-2 ($\mathcal{O}(N)$ Large Tensor Allocation & In-Place Argument Mutation)**: Allocating `Tensor[U64 * 160000 * 16]` (~20 MiB) and mutating a `Tensor` inside a function returning `()` or `Int` succeed in `< 50 ms` and preserve mutations in the caller.
3. **AC-3 (Cryptographic Hot-Loop Throughput in Pure Ridgun)**: 600,000 iterations of `sha256 raw (opad + (sha256 raw (ipad + u)))` (PBKDF2-HMAC-SHA256 core) and Argon2id / BlaMka tensor block compression execute in `< 1 s` in pure Ridgun.
4. **AC-4 (Field Reads and Small Calls, TS-COMP-011)**: 10 000 000 field reads, 10 000 000 calls to a function that matches its record parameter, and 10 000 000 turns of an empty self tail call loop run in under 400 ms on LLVM (`tests/cases/perf/field_reads_and_small_calls.rg`); borrowed parameters give the same results as owned ones with locals, temporaries, the same record twice, multi-variant constructors, tuples, strings and lists, and leak no blocks (`tests/cases/functions/borrowed_pattern_parameters.rg`).
