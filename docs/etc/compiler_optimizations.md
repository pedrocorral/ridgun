# Ridgun Compiler Optimization Catalog (`ridgunc`)

**Requirement Traceability**: `FR-COMP-002`, `FR-COMP-004`, `FR-COMP-010`, `FR-COMP-011`
**Primary Modules**: `src/main/ridgun/lib/compiler.rg`, `src/main/ridgun/lib/x86_64.rg`

## Overview
`ridgunc` includes a dedicated optimization pipeline operating at three levels:
1. **AST / High-Level IR Passes (`compiler.rg`)**: Function inlining, tuple-escape elimination, ephemeral expression fusion, and tail-call / tail-concatenation lowering.
2. **RMM1 / RMM2 Static Liveness & Ownership Passes (`compiler.rg`)**: Compile-time last-use analysis, zero-clone move propagation, and conditional pointer-identity drops (`RCmmAlias`).
3. **Native Codegen & Runtime Fast Paths (`compiler.rg`, `x86_64.rg`)**: Unboxed 1-cycle bitwise/rotate instructions, $\mathcal{O}(N)$ contiguous `Tensor` slab allocation, zero-allocation register-level `Tensor` indexing/mutation, and zero-allocation streaming/midstate hashing.

Every optimization in `ridgunc` is assigned a stable `OPT-NNN` identifier and documented below with its target pattern, safety preconditions, and complexity improvement.

---

## Catalog of Active Optimizations

| ID | Name | Phase | Target Pattern | Impact |
|---|---|---|---|---|
| `OPT-001` | Arithmetic Leaf & Tuple-Return Inlining | AST -> AST (`compiler.rg`) | Leaf arithmetic `fn ::` calls & `a, b = f ...` / `v_(0), v_(1) = f ...` | Eliminates call overhead and heap tuple box (`NMakeTuple`) |
| `OPT-002` | Self-TCO & Recursive Concatenation Move Lowering | AST -> Native IR (`compiler.rg`) | `f args` or `a + f args` / `a :: f args` in tail position | Constant $\mathcal{O}(1)$ stack frame reuse; moves local slots without cloning |
| `OPT-003` | RMM1 Static Liveness & Alias-Guarded Drop | AST -> Native IR (`compiler.rg`) | Local bindings `x = ...` at static last use | Deterministic deallocation without GC or read-borrow refcount traffic |
| `OPT-004` | $\mathcal{O}(N)$ Direct Contiguous `Tensor` Allocation | Native IR & x86_64 (`compiler.rg`, `x86_64.rg`) | `Tensor[T * d1]` and `Tensor[T * d1 * d2]` (`:tensor-zeros:`) | Replaces $\mathcal{O}(d_1^2)$ list concat with single slab/mmap allocation + `rep stosq` (`20 MiB` in `< 2 ms`) |
| `OPT-005` | Zero-Allocation `Tensor` Indexing & In-Place Mutation | Native IR & x86_64 (`compiler.rg`, `x86_64.rg`) | `m_(i)`, `m_(i, j)`, `m_(i, j) = v`, `m_(r,) = v`, `m_(,c)`, `A_ij xor B_ij` | Eliminates 3–6 heap `Vec` allocations and full-tensor `memcpy` per cell access; preserves in-place mutation across function arguments |
| `OPT-006` | Direct Binary `sha256_raw` & `sha256_raw (a + b)` Fusion | AST -> Native IR & x86_64 (`compiler.rg`, `x86_64.rg`) | `sha256 raw x` and `sha256 raw (a + b)` | Eliminates `Vec<u8>` padding alloc, `core::fmt::write` hex formatting, and `a + b` concat alloc; caches 64-byte block midstate for HMAC/PBKDF2 |
| `OPT-007` | Right-Associative List Cons Chain Fusion (`:`) | Parser AST (`parser.rg`, `typecheck.rg`) | `x:xs`, `a:b:c:xs`, `a:b:c:[]` | Fuses arbitrary-length `:` chains into a single prefix list allocation `[a, b, c] :: xs` or literal `[a, b, c]` |

---

## Detailed Pass Specifications

### `OPT-001` — Arithmetic Leaf & Tuple-Return Inlining
- **Location**: `collect_inline_expr_fns`, `inline_leaf_fndef_list`, `collect_inline_tuple_fns`, `inline_tuple_fndef_list` in `src/main/ridgun/lib/compiler.rg`.
- **Pattern**:
  1. Single-clause functions whose body is a compound pure arithmetic/bitwise expression (`+`, `-`, `*`, `/`, `%`, `and`, `or`, `xor`, `shl`, `shr`, `rotr`, `rotl`, `not`) called with variable or integer literal arguments.
  2. Single-clause functions consisting of pure arithmetic `StmtLet`/`StmtMut` bindings and returning a tuple `(e_1, ..., e_k)` whose call result is immediately destructured into variables (`a, b, c, d = f ...`) or tensor elements (`v_(0), v_(1), v_(2), v_(3) = f ...`).
- **Transformation**: Substitutes the arithmetic expression or expands the renamed local bindings directly into the caller's statement list and assigns each return expression `e_i` directly to its target variable or `StmtIndexAssign` without constructing an intermediate `ETuple` on the heap.

### `OPT-002` — Self-Tail-Call Optimization (TCO) & Recursive Concatenation Move Lowering
- **Location**: `lower_tail_return_cmm` (`ECall`, `EBin OpConcat`) in `src/main/ridgun/lib/compiler.rg`.
- **Pattern**:
  1. Direct self-recursive tail calls `f arg_1 ... arg_n` in any branch of a function body, guard, or block.
  2. Tail binary concatenation `lhs + rhs` / `lhs :: rhs` (`EBin OpConcat`) in recursive accumulators.
- **Transformation**:
  - Self-tail calls evaluate arguments into temporary slots (using `NMoveSlot` when a parameter has no further live uses), rebind parameter slots (`NRebindSlot`), clear temporaries, and jump to the function entry label (`NJump 0`).
  - Tail concatenations move local variables that are at their final use (`NMoveSlot`) before dropping remaining scope variables, avoiding redundant string/list clones across deep recursion (`RG-085`).

### `OPT-003` — RMM1 Static Liveness & Conditional Pointer-Identity Drop (`RCmmAlias`)
- **Location**: `cmm_expr_vars`, `cmm_stmts_vars`, `lower_cmm_drops`, `lower_unused_let_drop` in `src/main/ridgun/lib/compiler.rg`.
- **Pattern**: Local variables bound in sequential blocks, guards, and `||` blocks.
- **Transformation**: Computes the static live-after variable set at every statement boundary and emits `NCmmDropSlot` immediately after a variable's last use if it does not escape.

### `OPT-004` — $\mathcal{O}(N)$ Direct Contiguous `Tensor` Allocation (`:tensor-zeros:`)
- **Location**: `lower_make_one_dim_tensor`, `lower_make_two_dim_tensor` in `src/main/ridgun/lib/compiler.rg` and `NCallBuiltin 88` in `src/main/ridgun/lib/x86_64.rg`.
- **Problem Addressed**: Constructing a 1D or 2D tensor previously built nested Ridgun lists using `NBinOp 14` (`++`) in a loop ($\mathcal{O}(d_1^2)$ list copies) before flattening them in `rg_make_tensor`. For `Tensor[U64 * 160000 * 16]` (`d1 = 160,000`), $\mathcal{O}(d_1^2)$ required $1.28 \times 10^{10}$ list node copies.
- **Transformation**:
  - Emits `NCallBuiltin 88` with `(fill_val, d1)` (1D) or `(fill_val, d1, d2)` (2D).
  - Directly allocates the `shape` vector (`[d1]` or `[d1, d2]`) and the contiguous `data` buffer (`d1 * d2 * 8` bytes via `rg_alloc`, which uses `mmap` slabs for large buffers) and initializes all 64-bit elements in a single hardware `rep stosq` pass.

### `OPT-005` — Zero-Allocation `Tensor` Subscript Reads (`NIndex`), In-Place Mutation (`NIndexSet`), and Fast Bitwise Hadamard
- **Location**: `lower_tensor_helper`, `lower_bitwise_hadamard` in `src/main/ridgun/lib/compiler.rg` and `NIndex`, `NIndexSet`, `NCallBuiltin 90` in `src/main/ridgun/lib/x86_64.rg`.
- **Problem Addressed**:
  1. Scalar tensor reads `m_(i)` and `m_(i, j)` previously called `rg_index_get`, which allocated and freed 3 temporary heap `Vec`s (`slots`, `indices`, `strides`) on every access.
  2. Scalar tensor writes `m_(i) = v` and `m_(i, j) = v` previously called `rg_index_set`, which allocated 3 temporary heap `Vec`s AND cloned the entire tensor `data_box` (`Vec::from_slice`) into a newly allocated `RVal` box on every single element write. Aside from $\mathcal{O}(N)$ memory copying per element write, allocating a new `RVal` meant that mutating a `Tensor` passed as an argument to a function returning `()` or `Int` only updated the callee's local slot, leaving the caller's `Tensor` unmutated.
  3. Column slicing (`m_(,c)`) and element-wise bitwise Hadamard (`A_ij xor B_ij`) previously built intermediate lists with `++` or looped over 2D indices calling `NIndexSet`.
- **Transformation**:
  - **`NIndex` 1D/2D Fast Path**: When the base slot holds a `Tensor` (`tag == 5`) of rank equal to the index count (`1` or `2`) and the indices are tagged `Int`s, computes the flat row-major index (`i` or `i * cols + j`) in registers, bounds-checks against `data_len`, and loads `data_ptr[flat_idx]` directly with zero heap allocations.
  - **`NIndexSet` 1D/2D In-Place Fast Path**: When the base slot holds a `Tensor` (`tag == 5`) of rank `1` or `2` and the indices and value are tagged `Int`s, stores `val >> 1` directly into `data_ptr[flat_idx]` in-place and returns the existing `Tensor` `RVal` pointer. Both caller and callee share `data_box`, so mutations inside helper functions returning `()` or `Int` are immediately visible to the caller.
  - **Direct Column Slice & Flat Bitwise Hadamard**: `:tensor-col-slice:` pre-allocates a 1D tensor via `:tensor-zeros:` (`OPT-004`) and fills it in-place; `EHadamard` (`xor`, `and`, `or`) operates directly across the flat `data_ptr` arrays of the two input tensors (`NCallBuiltin 90`).

### `OPT-006` — Direct Binary `sha256_raw` & Ephemeral Concatenation Fusion (`sha256_raw (a + b)`)
- **Location**: `lower_call_expr` in `src/main/ridgun/lib/compiler.rg` and `NCallBuiltin 36`, `NCallBuiltin 89` in `src/main/ridgun/lib/x86_64.rg`.
- **Problem Addressed**:
  1. `sha256_raw` (`NCallBuiltin 36`) previously delegated to `sha256_str` (`b_id = 21`), which copied the input into a heap `Vec<u8>`, formatted the 8 `u32` digest words into a 64-byte ASCII hex `String` via `core::fmt::write`, and then parsed the 64 ASCII hex characters back into 32 raw bytes.
  2. In HMAC-SHA256 and PBKDF2-HMAC-SHA256 (`sha256 raw (opad + (sha256 raw (ipad + u)))`), each iteration performed two heap string concatenations (`ipad + u` and `opad + inner`) and re-compressed the constant 64-byte `ipad` and `opad` blocks from scratch 1,200,000 times.
- **Transformation**:
  - **Direct Binary Digest (`NCallBuiltin 36`)**: Compresses full 64-byte blocks directly from the input `String` slice without copying, pads the final block (1–2 blocks, 64–128 bytes) on the stack, byte-swaps (`bswap`) the 8 `u32` state words `H[0..7]` directly into a 32-byte stack buffer, and wraps it with `rg_new_str(rsp, 32)`.
  - **Ephemeral Concatenation Fusion (`sha256_raw (a + b)` -> `NCallBuiltin 89`)**: When `compiler.rg` lowers `ECall "sha256_raw" [EBin OpAdd a b]`, it evaluates `a` and `b` into adjacent slots without calling `NBinOp 0` (`rg_str_concat`). When `len(a) == 64` (the standard 512-bit block size used by HMAC `ipad`/`opad`), `NCallBuiltin 89` checks a 2-slot midstate cache keyed by the 64 bytes of `a`, reusing the post-block-0 SHA-256 state `H[0..7]` and compressing only the tail `b` on the stack with zero intermediate heap allocations.

### `OPT-007` — Right-Associative List Cons Chain Fusion (`a:b:c:xs`)
- **Location**: `parse_add_loop`, `parse_colon_combine` in `src/main/ridgun/lib/parser.rg` and `check_binop` in `src/main/ridgun/lib/typecheck.rg`.
- **Pattern**: Right-associative list constructor chains `a:b:c:xs` and `a:b:c:[]` in expressions (symmetric with `(a:b:c:xs)` in pattern matching).
- **Transformation**: Rather than allocating $k$ intermediate 1-element lists and performing $k$ sequential list concatenations, `parse_colon_combine` folds contiguous `:` chains into a single prefix `EList [a, b, c]` concatenated once with `xs` (`EBin OpConcat (EList [a, b, c]) xs`), or directly into `EList [a, b, c]` when the tail is `[]`.
