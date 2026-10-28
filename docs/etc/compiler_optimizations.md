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
| `OPT-008` | Inline LLVM IR Register Fast-Paths & Full 64-Bit `U64` Boxing | AST -> LLVM IR (`compiler.rg`, `llvm.rg`) | `NBinOp`, `NCloneSlot`, `NStoreSlot`, `NAsBool`, `@__rg_box_i64`, `str_char_at` | Keeps `Int`/`Bool` locals and `Tensor` loops in LLVM SSA registers (`opt -O2` + `llc -O2`); preserves full 64-bit `U64` (`0x8000000000000000` tag); zero-clone `str_char_at` byte reads |
| `OPT-009` | Unrolled Frame Prologue/Epilogue SROA & Direct `NCallFn` Tensor Maps | AST -> LLVM IR (`compiler.rg`, `llvm.rg`) | Function prologue/epilogue (`num_slots <= 24`), `NClearLocals`, `map f in m_(...)` | Eliminates escaping `%frame` pointers so `SROA` promotes all local slots to SSA registers and folds away immediate/zero drops; replaces indirect closure dispatch with direct `NCallFn` |
| `OPT-010` | `!invariant.load` Tensor Metadata CSE/LICM & `noalias` Allocators | LLVM IR (`llvm.rg`) | `@__rg_tensor_index_*`, `@__rg_adt_field_neg`, `@__rg_rt_alloc_buf` | Hoists `tag`, `rank`, `d0`, `d1`, `dptr`, and `len` loads and bounds checks once per `Tensor` across multi-access functions (`blamka_g`, `blamka_p16`) and loops |
| `OPT-011` | Hardware `rep movsb`/`stosq` & Zero-Boxing Row/Col Slice & Set (`92..95`) | AST -> LLVM IR (`compiler.rg`, `llvm.rg`) | `m_(r,)`, `m_(r,) = v`, `m_(,c)`, `m_(,c) = v`, `:tensor-zeros:` | Copies 2D rows via single hardware `rep movsb` (`0` allocations on `m_(r,) = v`) and columns via unboxed `i64` strided loops |
| `OPT-012` | SIMD-Vectorized Flat Hadamard (`+`,`-`,`*`,`and`,`or`,`xor`) & Fast 2D `NEinsum` | AST -> LLVM IR (`compiler.rg`, `llvm.rg`) | `A_ij + B_ij`, `A_ij * B_ij`, `A_ij xor B_ij`, `A_ik @ B_kj` | Hoists `op_id` switch into 6 branch-free vectorizable loops (`vpaddq`/`vpmullq`/`vpxor`) and runs 2D matmul in cache-friendly unit-stride `i-k-j` order |
| `OPT-013` | Direct SSA Register Calling Convention (`@__rg_fn_{fid}_reg`) & Caller Frame Escape Elimination | Native IR -> LLVM IR (`compiler.rg`, `llvm.rg`) | Direct function calls `NCallFn fid start_slot count` (`fid >= 5`, `arity <= 8`) | Passes arguments in hardware registers (`rdi..r9`), stops caller `%frame` pointers from escaping on calls (unlocking cross-call `SROA`), and enables LLVM `CGSCC` cross-function inlining |
| `OPT-014` | AST-Level Higher-Order Function (`fold`, `map`, `filter`) Direct-Call Specialization | AST -> AST (`compiler.rg`) | `fold f init xs`, `map f xs`, `filter p xs` where `f`/`p` is a known top-level function or lambda | Replaces indirect runtime closure dispatch (`NCallIndirect1` / `NCallIndirect2`) with specialized direct-call (`OPT-013`) and self-TCO (`OPT-002`) loops |

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

### `OPT-008` — Inline LLVM IR Register Fast-Paths (`NBinOp`, Slot Ops, 64-Bit `U64` Boxing, `str_char_at`)
- **Location**: `lower_call_expr` (`str_char_at` -> `NCallBuiltin 91`) in `src/main/ridgun/lib/compiler.rg` and `@__rg_fast_bin_op`, `@__rg_fast_clone_slot`, `@__rg_fast_store_slot`, `@__rg_fast_rebind_slot`, `@__rg_fast_cmm_drop_slot`, `@__rg_fast_drop_val`, `@__rg_fast_as_bool`, `@__rg_box_i64`, `@__rg_str_char_at_fast`, `@__rg_builtin_str_char_at` in `src/main/ridgun/lib/llvm.rg`.
- **Transformation**:
  1. **Register-Promoted `NBinOp` & Slot Fast-Paths**: Executes integer arithmetic/bitwise/rotate/comparison ops (`+`, `-`, `*`, `/`, `%`, `==`, `!=`, `>`, `<`, `>=`, `<=`, `and`, `or`, `xor`, `shl`, `shr`, `rotr` via `@llvm.fshr.i64`, `rotl` via `@llvm.fshl.i64`) and immediate slot loads/stores directly in LLVM IR, running `opt -O2` (SROA + Mem2Reg + CGSCC Inliner) before `llc -O2` so local slots `%frame[i]` and `%acc` are promoted to hardware registers (`2,000 x blamka p16` = 16,000 BlaMka G rounds in `13 ms`).
  2. **Full 64-Bit `U64` Heap Boxing (`@__rg_box_i64_slow`)**: Stores `-9223372036854775808` (`0x8000000000000000`) at offset 0 of the `RVal` buffer when boxing 64-bit integers with `bit 63 != bit 62` (`0x4000000000000000 .. 0xBFFFFFFFFFFFFFFF`), and unboxes heap `U64` operands in `@__rg_bin_op_u64_or_slow` and `@__rg_not_op` so `Tensor[U64 * ...]` supports all 64 bits without truncation.
  3. **Inline `str_char_at` Local Borrow (`NCallBuiltin 91`)**: When `str_char_at` is called on a local variable `s`, reads the byte directly from `%frame[s_slot]`'s `dptr` in LLVM IR (`@__rg_str_char_at_fast`) without cloning or dropping `s`.

### `OPT-009` — Unrolled Constant-Offset Frame Prologue/Epilogue (`SROA` Unlock) & Direct `NCallFn` Tensor Maps
- **Location**: `tensor_map_call_instr` in `src/main/ridgun/lib/compiler.rg` and `llvm_unroll_init_frame`, `llvm_unroll_clear_locals`, `llvm_unroll_epilogue`, `emit_llvm_fn`, `@__rg_tensor_index_*_slow` in `src/main/ridgun/lib/llvm.rg`.
- **Transformation**:
  1. Unrolls function prologue (`0..arity-1` from `%args`, `arity..num_slots-1` zeroed), `NClearLocals` (`<= 8` slots), and single-exit function epilogue (`epilogue_exit:`) into constant-offset `getelementptr` + `@__rg_fast_drop_val` calls for non-TCO functions with `num_slots <= 24`, and passes `i64` values by value to `@__rg_tensor_index_*_slow`. Because `ptr %frame` never escapes to external `.rt` functions, LLVM `SROA` splits `%frame` into individual SSA registers and `InstCombine` folds away `@__rg_fast_drop_val` on `0` or immediate `Int`/`Bool` values at compile time.
  2. Emits direct `NCallFn` instead of `NCallIndirect1` in `:tensor-map-rows-in:`, `:tensor-map-cols-in:`, and `:tensor-map-elems-in:` when the mapped function is a known top-level unary function, allowing LLVM's CGSCC inliner to inline the mapped body directly into the loop.

### `OPT-010` — `!invariant.load !0` on Immutable `Tensor` Metadata & `noalias` Buffer Allocation
- **Location**: `@__rg_adt_field_neg`, `@__rg_tensor_index_1d`, `@__rg_tensor_index_2d`, `@__rg_tensor_index_set_1d`, `@__rg_tensor_index_set_2d`, `llvm_runtime_declarations` in `src/main/ridgun/lib/llvm.rg`.
- **Transformation**: Annotates all loads of immutable `Tensor` metadata (`tag`, `shdr`, `dhdr`, `sptr`, `rk`, `d0`, `d1`, `dptr`, `len`) with `!invariant.load !0` and marks `@__rg_rt_alloc_buf` / `@__rg_rt_box_rc_vec` return pointers `noalias`. `opt -O2` (`EarlyCSE` / `GVN` / `LICM`) deduplicates and hoists all pointer indirections and tag/rank/bounds checks even across stores to `dptr[idx]`.

### `OPT-011` — Hardware `rep movsb`/`rep stosb`/`rep stosq` & Zero-Boxing Row/Col Slice & Set Built-ins (`NCallBuiltin 92..95`)
- **Location**: `lower_tensor_helper`, `lower_tensor_set_row_slots`, `lower_tensor_get_col_slots`, `lower_tensor_set_col_slots` in `src/main/ridgun/lib/compiler.rg` and `@__rg_memcpy`, `@__rg_memset`, `@__rg_builtin_tensor_fill`, `@__rg_builtin_tensor_row_slice`, `@__rg_builtin_tensor_set_row`, `@__rg_builtin_tensor_col_slice`, `@__rg_builtin_tensor_set_col` in `src/main/ridgun/lib/llvm.rg`.
- **Transformation**:
  1. Replaces byte-by-byte loops in `@__rg_memcpy` and `@__rg_memset` with `inlinehint` hardware `rep movsb` / `rep stosb` and uses `rep stosq` in `@__rg_builtin_tensor_fill`.
  2. Lowers 2D row slicing `m_(r,)` (`92`) and in-place row assignment `m_(r,) = v` (`93`) to contiguous `@__rg_memcpy` (`rep movsb` of `cols * 8` bytes, with zero heap allocations on `m_(r,) = v`), and lowers 2D column slicing `m_(,c)` (`94`) and in-place column assignment `m_(,c) = v` (`95`) to unboxed `i64` strided loops.

### `OPT-012` — SIMD-Vectorized Flat Hadamard (`+`, `-`, `*`, `and`, `or`, `xor`) & Cache-Friendly 2D `NEinsum` (`@__rg_fast_einsum`)
- **Location**: `lower_expr` (`EHadamard`) in `src/main/ridgun/lib/compiler.rg` and `@__rg_builtin_tensor_bitop`, `@__rg_fast_einsum` in `src/main/ridgun/lib/llvm.rg`.
- **Transformation**:
  1. Routes flat (`s1 == s2`) arithmetic Hadamard (`+`, `-`, `*`) as well as bitwise Hadamard (`and`, `or`, `xor`) to `@__rg_builtin_tensor_bitop` (`NCallBuiltin 90`) and hoists `switch i64 %op_id` outside the loop into 6 branch-free loops so `opt -O2` (`LoopVectorize`) emits AVX2/SSE2 SIMD instructions (`vpaddq`, `vpsubq`, `vpmullq`, `vpand`, `vpor`, `vpxor`).
  2. Executes 2D matrix multiplication (`A_ik @ B_kj` / `A_ij @ B_jk`) in `@__rg_fast_einsum` using cache-friendly unit-stride `i-k-j` loop order over unboxed `i64` buffers.

### `OPT-013` — Direct SSA Register Calling Convention (`@__rg_fn_{fid}_reg`) & Caller Frame Escape Elimination
- **Location**: `emit_llvm_fn`, `emit_llvm_instr` (`NCallFn`) in `src/main/ridgun/lib/llvm.rg`.
- **Problem Addressed**:
  1. Previously, every user function had a single entry signature `define i64 @__rg_fn_{fid}(ptr %args)`, and every direct call `NCallFn fid start_slot count` computed `%s = getelementptr [N x i64], ptr %frame, i64 0, i64 start_slot` and passed `ptr %s` to `@__rg_fn_{fid}(ptr %s)`.
  2. Passing a pointer into `%frame` to a function call caused LLVM's alias analysis to treat the caller's `%frame` array as **address-taken / escaped** across calls, preventing `SROA` / `Mem2Reg` from promoting caller local variables into SSA registers in non-leaf functions and forcing every argument pass through stack memory.
- **Transformation**:
  1. **Dual Entry Point (`@__rg_fn_{fid}_reg` + `@__rg_fn_{fid}` ABI wrapper)**: For every user function (`fid >= 5`) with `arity <= 8`, `llvm.rg` emits the implementation in `define i64 @__rg_fn_{fid}_reg(i64 %arg_0, ..., i64 %arg_{k-1})` (annotated with `inlinehint` for compact functions) and initializes `%frame[0..arity-1]` directly from the SSA register parameters `%arg_0 .. %arg_{k-1}`.
  2. **Indirect/Runtime Compatibility Wrapper**: `@__rg_fn_{fid}(ptr %args)` is emitted as a thin wrapper that loads `%av_0 .. %av_{k-1}` from `ptr %args`, zeroes `ptr %args[0..k-1]` (`store i64 0`, preserving the RMM move contract for indirect calls via `@__rg_page0`, `NCallIndirect1`, `NCallIndirect2`, and `spawn`), and calls `@__rg_fn_{fid}_reg(%av_0, ..., %av_{k-1})`.
  3. **Direct Register Calls at `NCallFn`**: When `NCallFn fid start_slot count` targets a user function with `fid >= 5` and `count <= 8` matching the function's arity, the caller loads `%av_0 .. %av_{count-1}` from `%frame[start_slot .. start_slot + count - 1]`, immediately zeroes those caller frame slots (`store i64 0, ptr %ap_i, align 8`), and calls `call i64 @__rg_fn_{fid}_reg(i64 %av_0, ...)`. Because `ptr %frame` never escapes to `NCallFn`, LLVM `SROA` promotes `%frame` to SSA registers across function calls and `CGSCC` inlines small helper functions directly into callers.

### `OPT-014` — AST-Level Higher-Order Function (`fold`, `map`, `filter`) Direct-Call Specialization
- **Location**: `specialize_hof_fndef_list` in `src/main/ridgun/lib/compiler.rg`.
- **Problem Addressed**: Standard list pipelines `xs map f -> filter p -> fold g init` previously lowered to runtime built-ins (`NCallBuiltin 4` / `5` / `6`) that invoked `f`, `p`, and `g` via indirect runtime dispatch (`NCallIndirect1` / `NCallIndirect2` through `@__rg_page0` and `ptr %args`) and allocated intermediate closures or list structures through generic runtime helpers.
- **Transformation**:
  - When `fold f init xs`, `map f xs`, or `filter p xs` is called where the first argument `f`/`p` is an `EVar fn_name` referencing a known top-level function (including lifted lambdas `__rg_lambda_*` after lambda lifting), `compiler.rg` synthesizes a specialized recursive helper function (`__rg_spec_fold_{id}`, `__rg_spec_map_{id}`, `__rg_spec_filter_{id}`) that invokes `fn_name` via a direct `ECall` and replaces the HOF call site with a direct call to the specialized helper.
  - Because the synthesized helper is a standard `FnDef`, it automatically benefits from `OPT-002` (self-TCO loop for `fold`), `OPT-003` (`RMM1` static last-use drops), `OPT-009` (unrolled frame `SROA`), and `OPT-013` (`@__rg_fn_{fid}_reg` register calling convention and cross-function inlining of `fn_name` into the loop).

---

## RMM1 / RMM2 Invariants & Future RMM Evolution Guide

> **Why this section exists**: All optimizations in `OPT-001`..`OPT-014` are designed to be 100% transparent to Ridgun's deterministic memory management models (`RMM1` static last-use deallocation and `RMM2` scope-exit reference counting defined in `FR-COMP-002`). When `RMM1` or `RMM2` is modified or replaced in the future (for example, to introduce unboxed 64-bit primitive frame slots, static borrow lifetimes, or region-based reclamation), the following contracts and coupling points between the optimizer/codegen and the RMM **must** be taken into account.

### 1. Value Representation Contract (`i64` Tagged Word vs. Heap `RVal*`)
Currently, every slot `%frame[i]`, register `%acc`, and `@__rg_fn_{fid}_reg` parameter `%arg_i` holds a single 64-bit word with the following LSB tag discipline:
- **Immediate scalar (`(val & 1) == 1`)**: 63-bit signed `Int` (`(val << 1) | 1`), `Bool` (`1` = `False`, `3` = `True`), or `()` (`1`). All drop/clone operations (`@__rg_fast_drop_val`, `@__rg_fast_cmm_drop_slot`, `@__rg_fast_clone_slot`) treat `(val & 1) == 1` or `val == 0` as a **compile-time or 1-cycle no-op**.
- **Null / Empty slot (`val == 0`)**: Uninitialized or moved-from frame slot; dropping `0` is a no-op.
- **Heap `RVal` pointer (`val != 0` and `(val & 1) == 0`)**: Pointer to a 24-byte `RVal` header (`[offset -8: i64 refcount, offset 0: i64 tag, offset 8: i64 payload1, offset 16: i64 payload2]`). Note that full 64-bit integers (`U64` where `bit 63 != bit 62`, per `OPT-008`) are heap-boxed with `tag == -9223372036854775808` (`0x8000000000000000`).

**Impact on future RMM / Unboxing changes**:
- If a future RMM introduces **untagged 64-bit frame slots** (e.g., raw `i64` / `u64` / `f64` in `%frame[i]` without LSB tagging), an untagged even integer `42` would look like a heap pointer `(val & 1) == 0` and cause a segfault if passed to `@__rg_fast_drop_val` or `@__rg_fast_store_slot`.
- **Required adaptation when unboxing slots**: Attach a static `SlotDropKind` (`NoDropScalar` vs. `ManagedRVal`) to each slot in `NativeFn` (`compiler.rg` -> `llvm.rg`). For `NoDropScalar` slots:
  - Omit `@__rg_fast_drop_val` in `llvm_unroll_epilogue` (`OPT-009`), `llvm_unroll_clear_locals`, and `NCmmDropSlot` (`OPT-003`).
  - Use plain `store i64` instead of `@__rg_fast_store_slot` / `@__rg_fast_rebind_slot` (`OPT-008`).
  - Box/unbox at polymorphic (`A..Z`) or heap container (`List`, `Tuple`, ADT field) boundaries.

### 2. Call-Boundary Ownership Transfer Contract (`OPT-002`, `OPT-009`, `OPT-013`)
Under the current `RMM1` / `RMM2` lowering in `compiler.rg`:
1. **Caller Preparation (`lower_call_args`)**: Before emitting `NCallFn fid start_slot count`, the caller evaluates each argument into `%frame[start_slot + i]`. If an argument is a local variable at its static last use (`RMM1`), the caller uses `NMoveSlot` (moving the pointer and zeroing the source local slot); otherwise it uses `NCloneSlot` (incrementing the heap refcount by `+1` for heap `RVal`s).
2. **Ownership Transfer on Call (`OPT-013`)**: The callee takes ownership of the `count` values placed in `start_slot .. start_slot + count - 1` and stores them in its own parameter slots `%frame[0 .. arity - 1]`.
   - In **indirect calls** via `@__rg_fn_{fid}(ptr %args)` (or `llvm_unroll_init_frame` when reading `ptr %args`), the callee zeroes `args[0..arity-1]` (`store i64 0, ptr %ap_i`) as it transfers the words into its own frame.
   - In **direct register calls** via `@__rg_fn_{fid}_reg(i64 %arg_0, ...)` (`OPT-013`), the **caller** loads `%av_i = %frame[start_slot + i]` and **immediately zeroes `%frame[start_slot + i]` (`store i64 0`)** before calling `@__rg_fn_{fid}_reg`.
   - **Why zeroing caller `start_slot + i` is mandatory**: If the caller did not zero `%frame[start_slot + i]` after passing `%av_i` by value into `@__rg_fn_{fid}_reg`, both the callee's epilogue (which drops `%frame[0..arity-1]`) AND the caller's epilogue (or subsequent `NStoreSlot` overwriting `%frame[start_slot + i]`) would drop the same heap `RVal` pointer, causing a double-free.
3. **Callee Return & Epilogue (`OPT-009`)**: Before jumping to `epilogue_exit:`, the return expression's slot is moved into `%acc` (`NMoveSlot` zeroes that slot in `%frame`), and `llvm_unroll_epilogue` drops all remaining non-zero slots in `%frame[0..num_slots-1]`.

**Impact on future RMM changes**:
- If a future RMM changes function parameters from **callee-owned (sink/move)** to **caller-owned read-only borrows** (so the caller does not `NCloneSlot` non-last-use arguments and the callee does not drop untouched parameters `0..arity-1` on exit):
  1. `llvm_unroll_epilogue` (`OPT-009`) and `@__rg_rt_epilogue` must only drop slots `arity .. num_slots - 1` (or parameter slots that were mutated via `StmtMut` / `NRebindSlot`).
  2. Returning a parameter directly (`fn id x = x`) must increment its refcount (`NCloneSlot`) before `epilogue_exit:` since the caller still owns the borrowed parameter.
  3. Direct `NCallFn` (`OPT-013`) must only zero `%frame[start_slot + i]` if `start_slot + i` holds a temporary expression result rather than a direct borrow slot.

### 3. Alias-Guarded Drops (`RCmmAlias` in `OPT-003`) & In-Place `Tensor` Mutation (`OPT-005`)
- **In-Place `Tensor` Aliasing (`OPT-005`)**: `NIndexSet` (`m_(i, j) = v`), `:tensor-set-row:` (`93`), and `:tensor-set-col:` (`95`) mutate the `Tensor`'s underlying `data_ptr` buffer in-place without allocating a new `RVal` wrapper. Therefore, passing a `Tensor` to a helper function shares the same `data_box` pointer between caller and callee.
- **Future CoW / Uniqueness RMM Note**: If a future RMM introduces copy-on-write (CoW) uniqueness checks (`refcount == 1`) on `Tensor` mutation, note that when a caller passes a `Tensor` variable `m` that is still live after the call (`m` is read after `helper m`), `lower_call_args` clones `m` (`refcount` becomes `2` during `helper`). To preserve in-place mutation semantics across helper calls (`FR-COMP-011 §3`), either `Tensor` arguments must be passed as borrowed references (`+0` refcount) or `Tensor` buffers must retain shared-slice semantics during in-place helper calls.

### 4. AST-Level HOF Specialization (`OPT-014`) & Closure Capture Evolution
- `OPT-014` specializes `fold f init xs`, `map f xs`, and `filter p xs` when `f`/`p` is a top-level function or a lambda lifted with **zero** captured environment variables (`free_vars == []`).
- When a lambda captures outer local variables, `lift_expr` transforms it into an explicit environment tuple/closure call (`EClosure`), which is NOT matched as a bare `EVar fn_name` by `OPT-014` and therefore safely falls back to the runtime closure dispatcher (`NCallIndirect1` / `NCallIndirect2`).
- If a future RMM changes how closure environments are allocated (e.g., stack-allocated non-escaping closure environments), `OPT-014` can be extended to pass the borrowed environment pointer directly as an extra parameter to `__rg_spec_fold_*` / `__rg_spec_map_*` / `__rg_spec_filter_*`.

