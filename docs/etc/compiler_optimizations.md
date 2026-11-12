# Ridgun Compiler Optimization Catalog (`ridgunc`)

**Requirement Traceability**: `FR-COMP-002`, `FR-COMP-004`, `FR-COMP-010`, `FR-COMP-011`
**Primary Modules**: `src/main/ridgun/lib/compiler.ridgun`, `src/main/ridgun/lib/x86_64.ridgun`

## Overview
`ridgunc` includes a dedicated optimization pipeline operating at three levels:
1. **AST / High-Level IR Passes (`compiler.ridgun`)**: Function inlining, tuple-escape elimination, ephemeral expression fusion, and tail-call / tail-concatenation lowering.
2. **RMM1 / RMM2 Static Liveness & Ownership Passes (`compiler.ridgun`)**: Compile-time last-use analysis, zero-clone move propagation, and conditional pointer-identity drops (`RCmmAlias`).
3. **Native Codegen & Runtime Fast Paths (`compiler.ridgun`, `x86_64.ridgun`)**: Unboxed 1-cycle bitwise/rotate instructions, $\mathcal{O}(N)$ contiguous `Tensor` slab allocation, zero-allocation register-level `Tensor` indexing/mutation, and zero-allocation streaming/midstate hashing.

Every optimization in `ridgunc` is assigned a stable `OPT-NNN` identifier and documented below with its target pattern, safety preconditions, and complexity improvement.

---

## Catalog of Active Optimizations

| ID | Name | Phase | Target Pattern | Impact |
|---|---|---|---|---|
| `OPT-001` | Arithmetic Leaf & Tuple-Return Inlining | AST -> AST (`compiler.ridgun`) | Leaf arithmetic `fn ::` calls & `a, b = f ...` / `v_(0), v_(1) = f ...` | Eliminates call overhead and heap tuple box (`NMakeTuple`) |
| `OPT-002` | Self-TCO & Recursive Concatenation Move Lowering | AST -> Native IR (`compiler.ridgun`) | `f args` or `a + f args` / `a :: f args` in tail position | Constant $\mathcal{O}(1)$ stack frame reuse; moves local slots without cloning |
| `OPT-003` | RMM1 Static Liveness & Alias-Guarded Drop | AST -> Native IR (`compiler.ridgun`) | Local bindings `x = ...` at static last use | Deterministic deallocation without GC or read-borrow refcount traffic |
| `OPT-004` | $\mathcal{O}(N)$ Direct Contiguous `Tensor` Allocation | Native IR & x86_64 (`compiler.ridgun`, `x86_64.ridgun`) | `Tensor[T * d1]` and `Tensor[T * d1 * d2]` (`:tensor-zeros:`) | Replaces $\mathcal{O}(d_1^2)$ list concat with single slab/mmap allocation + `rep stosq` (`20 MiB` in `< 2 ms`) |
| `OPT-005` | Zero-Allocation `Tensor` Indexing & In-Place Mutation | Native IR & x86_64 (`compiler.ridgun`, `x86_64.ridgun`) | `m_(i)`, `m_(i, j)`, `m_(i, j) = v`, `m_(r,) = v`, `m_(,c)`, `A_ij xor B_ij` | Eliminates 3–6 heap `Vec` allocations and full-tensor `memcpy` per cell access; preserves in-place mutation across function arguments |
| `OPT-006` | Direct Binary `sha256_raw` & `sha256_raw (a + b)` Fusion | AST -> Native IR & x86_64 (`compiler.ridgun`, `x86_64.ridgun`) | `sha256 raw x` and `sha256 raw (a + b)` | Eliminates `Vec<u8>` padding alloc, `core::fmt::write` hex formatting, and `a + b` concat alloc; caches 64-byte block midstate for HMAC/PBKDF2 |
| `OPT-007` | Right-Associative List Cons Chain Fusion (`:`) | Parser AST (`parser.ridgun`, `typecheck.ridgun`) | `x:xs`, `a:b:c:xs`, `a:b:c:[]` | Fuses arbitrary-length `:` chains into a single prefix list allocation `[a, b, c] :: xs` or literal `[a, b, c]` |
| `OPT-008` | Inline LLVM IR Register Fast-Paths & Full 64-Bit `U64` Boxing | AST -> LLVM IR (`compiler.ridgun`, `llvm.ridgun`) | `NBinOp`, `NCloneSlot`, `NStoreSlot`, `NAsBool`, `@__rg_box_i64`, `str_char_at` | Keeps `Int`/`Bool` locals and `Tensor` loops in LLVM SSA registers (`opt -O2` + `llc -O2`); preserves full 64-bit `U64` (`0x8000000000000000` tag); zero-clone `str_char_at` byte reads |
| `OPT-009` | Unrolled Frame Prologue/Epilogue SROA & Direct `NCallFn` Tensor Maps | AST -> LLVM IR (`compiler.ridgun`, `llvm.ridgun`) | Function prologue/epilogue (`num_slots <= 24`), `NClearLocals`, `map f in m_(...)` | Eliminates escaping `%frame` pointers so `SROA` promotes all local slots to SSA registers and folds away immediate/zero drops; replaces indirect closure dispatch with direct `NCallFn` |
| `OPT-010` | `!invariant.load` Tensor Metadata CSE/LICM & `noalias` Allocators | LLVM IR (`llvm.ridgun`) | `@__rg_tensor_index_*`, `@__rg_adt_field_neg`, `@__rg_rt_alloc_buf` | Hoists `tag`, `rank`, `d0`, `d1`, `dptr`, and `len` loads and bounds checks once per `Tensor` across multi-access functions (`blamka_g`, `blamka_p16`) and loops |
| `OPT-011` | Hardware `rep movsb`/`stosq` & Zero-Boxing Row/Col Slice & Set (`92..95`) | AST -> LLVM IR (`compiler.ridgun`, `llvm.ridgun`) | `m_(r,)`, `m_(r,) = v`, `m_(,c)`, `m_(,c) = v`, `:tensor-zeros:` | Copies 2D rows via single hardware `rep movsb` (`0` allocations on `m_(r,) = v`) and columns via unboxed `i64` strided loops |
| `OPT-012` | SIMD-Vectorized Flat Hadamard (`+`,`-`,`*`,`and`,`or`,`xor`) & Fast 2D `NEinsum` | AST -> LLVM IR (`compiler.ridgun`, `llvm.ridgun`) | `A_ij + B_ij`, `A_ij * B_ij`, `A_ij xor B_ij`, `A_ik @ B_kj` | Hoists `op_id` switch into 6 branch-free vectorizable loops (`vpaddq`/`vpmullq`/`vpxor`) and runs 2D matmul in cache-friendly unit-stride `i-k-j` order |
| `OPT-013` | Direct SSA Register Calling Convention (`@__rg_fn_{fid}_reg`) & Caller Frame Escape Elimination | Native IR -> LLVM IR (`compiler.ridgun`, `llvm.ridgun`) | Direct function calls `NCallFn fid start_slot count` (`fid >= 5`, `arity <= 8`) | Passes arguments in hardware registers (`rdi..r9`), stops caller `%frame` pointers from escaping on calls (unlocking cross-call `SROA`), and enables LLVM `CGSCC` cross-function inlining |
| `OPT-014` | AST-Level Higher-Order Function (`fold`, `map`, `filter`) Direct-Call Specialization | AST -> AST (`compiler.ridgun`) | `fold f init xs`, `map f xs`, `filter p xs` where `f`/`p` is a known top-level function or lambda | Replaces indirect runtime closure dispatch (`NCallIndirect1` / `NCallIndirect2`) with specialized direct-call (`OPT-013`) and self-TCO (`OPT-002`) loops |
| `OPT-015` | Inline Tail-Call Frame Copy & Epilogue for Small Frames | Native IR -> LLVM IR (`llvm.ridgun`) | Functions with a self tail call (`NTailCall`), `num_slots <= 24` | Replaces `@__rg_rt_tco_copy`, `@__rg_rt_epilogue` and `@__rg_rt_clear_locals` with unrolled loads, stores and `@__rg_fast_drop_val`; `%frame` no longer escapes, so loops run in registers |
| `OPT-016` | Direct Record Field Reads & Inline ADT Match/Field Fast Paths | AST -> Native IR -> LLVM IR (`compiler.ridgun`, `llvm.ridgun`) | `field r` (record accessor call), constructor patterns, `NAdtField slot k`, `NMatchAdt` | Reads the field from the record's slot without a call, a clone or a drop of the record; tag and field reads inline in LLVM |
| `OPT-017` | Deferred Parameter Move in Self Tail Calls | AST -> Native IR (`compiler.ridgun`) | `loop r (j + 1) (acc + field r)`: a parameter passed on and read by a later argument | Moves the parameter into its argument slot after the other arguments instead of cloning it |
| `OPT-018` | Borrowed Pattern Parameters | AST -> Native IR (`compiler.ridgun`, all backends) | Parameters that every clause matches with a constructor, tuple, `[]`, string or `_` pattern | The caller passes a local without a clone and the callee empties the slot without a drop (`NPeekSlot`, `NForgetSlot`) |
| `OPT-019` | Tail Calls Between Different Functions | AST -> Native IR -> all backends (`compiler.ridgun`, `llvm.ridgun`, `x86_64.ridgun`) | A direct call to another function in tail position (`loop` -> `step` -> `loop`, unit functions calling unit functions) | Releases the caller's frame before the call: any number of rounds in constant stack and memory (was about 200 bytes per round, crash at 3 000 000) |
| `OPT-020` | In-Place String Append in Tail Calls | AST -> Native IR -> runtime extension (`typecheck.ridgun`, `compiler.ridgun`, builtin 121) | `loop (n - 1) (acc + x)` and chains `acc + sep + x` in a tail position, `acc` a String | Moves `acc` on its last use and appends in place when it has one owner, with a doubling buffer: linear instead of quadratic (100 000 appends 2.3 s -> 3 ms) |

---

## Detailed Pass Specifications

### `OPT-001` — Arithmetic Leaf & Tuple-Return Inlining
- **Location**: `collect_inline_expr_fns`, `inline_leaf_fndef_list`, `collect_inline_tuple_fns`, `inline_tuple_fndef_list` in `src/main/ridgun/lib/compiler.ridgun`.
- **Pattern**:
  1. Single-clause functions whose body is a compound pure arithmetic/bitwise expression (`+`, `-`, `*`, `/`, `%`, `and`, `or`, `xor`, `shl`, `shr`, `rotr`, `rotl`, `not`) called with variable or integer literal arguments.
  2. Single-clause functions consisting of pure arithmetic `StmtLet`/`StmtMut` bindings and returning a tuple `(e_1, ..., e_k)` whose call result is immediately destructured into variables (`a, b, c, d = f ...`) or tensor elements (`v_(0), v_(1), v_(2), v_(3) = f ...`).
- **Transformation**: Substitutes the arithmetic expression or expands the renamed local bindings directly into the caller's statement list and assigns each return expression `e_i` directly to its target variable or `StmtIndexAssign` without constructing an intermediate `ETuple` on the heap.

### `OPT-002` — Self-Tail-Call Optimization (TCO) & Recursive Concatenation Move Lowering
- **Location**: `lower_tail_return_cmm` (`ECall`, `EBin OpConcat`) in `src/main/ridgun/lib/compiler.ridgun`.
- **Pattern**:
  1. Direct self-recursive tail calls `f arg_1 ... arg_n` in any branch of a function body, guard, or block.
  2. Tail binary concatenation `lhs + rhs` / `lhs :: rhs` (`EBin OpConcat`) in recursive accumulators.
- **Transformation**:
  - Self-tail calls evaluate arguments into temporary slots (using `NMoveSlot` when a parameter has no further live uses), rebind parameter slots (`NRebindSlot`), clear temporaries, and jump to the function entry label (`NJump 0`).
  - Tail concatenations move local variables that are at their final use (`NMoveSlot`) before dropping remaining scope variables, avoiding redundant string/list clones across deep recursion (`RG-085`).

### `OPT-003` — RMM1 Static Liveness & Conditional Pointer-Identity Drop (`RCmmAlias`)
- **Location**: `cmm_expr_vars`, `cmm_stmts_vars`, `lower_cmm_drops`, `lower_unused_let_drop` in `src/main/ridgun/lib/compiler.ridgun`.
- **Pattern**: Local variables bound in sequential blocks, guards, and `||` blocks.
- **Transformation**: Computes the static live-after variable set at every statement boundary and emits `NCmmDropSlot` immediately after a variable's last use if it does not escape.

### `OPT-004` — $\mathcal{O}(N)$ Direct Contiguous `Tensor` Allocation (`:tensor-zeros:`)
- **Location**: `lower_make_one_dim_tensor`, `lower_make_two_dim_tensor` in `src/main/ridgun/lib/compiler.ridgun` and `NCallBuiltin 88` in `src/main/ridgun/lib/x86_64.ridgun`.
- **Problem Addressed**: Constructing a 1D or 2D tensor previously built nested Ridgun lists using `NBinOp 14` (`++`) in a loop ($\mathcal{O}(d_1^2)$ list copies) before flattening them in `rg_make_tensor`. For `Tensor[U64 * 160000 * 16]` (`d1 = 160,000`), $\mathcal{O}(d_1^2)$ required $1.28 \times 10^{10}$ list node copies.
- **Transformation**:
  - Emits `NCallBuiltin 88` with `(fill_val, d1)` (1D) or `(fill_val, d1, d2)` (2D).
  - Directly allocates the `shape` vector (`[d1]` or `[d1, d2]`) and the contiguous `data` buffer (`d1 * d2 * 8` bytes via `rg_alloc`, which uses `mmap` slabs for large buffers) and initializes all 64-bit elements in a single hardware `rep stosq` pass.

### `OPT-005` — Zero-Allocation `Tensor` Subscript Reads (`NIndex`), In-Place Mutation (`NIndexSet`), and Fast Bitwise Hadamard
- **Location**: `lower_tensor_helper`, `lower_bitwise_hadamard` in `src/main/ridgun/lib/compiler.ridgun` and `NIndex`, `NIndexSet`, `NCallBuiltin 90` in `src/main/ridgun/lib/x86_64.ridgun`.
- **Problem Addressed**:
  1. Scalar tensor reads `m_(i)` and `m_(i, j)` previously called `rg_index_get`, which allocated and freed 3 temporary heap `Vec`s (`slots`, `indices`, `strides`) on every access.
  2. Scalar tensor writes `m_(i) = v` and `m_(i, j) = v` previously called `rg_index_set`, which allocated 3 temporary heap `Vec`s AND cloned the entire tensor `data_box` (`Vec::from_slice`) into a newly allocated `RVal` box on every single element write. Aside from $\mathcal{O}(N)$ memory copying per element write, allocating a new `RVal` meant that mutating a `Tensor` passed as an argument to a function returning `()` or `Int` only updated the callee's local slot, leaving the caller's `Tensor` unmutated.
  3. Column slicing (`m_(,c)`) and element-wise bitwise Hadamard (`A_ij xor B_ij`) previously built intermediate lists with `++` or looped over 2D indices calling `NIndexSet`.
- **Transformation**:
  - **`NIndex` 1D/2D Fast Path**: When the base slot holds a `Tensor` (`tag == 5`) of rank equal to the index count (`1` or `2`) and the indices are tagged `Int`s, computes the flat row-major index (`i` or `i * cols + j`) in registers, bounds-checks against `data_len`, and loads `data_ptr[flat_idx]` directly with zero heap allocations.
  - **`NIndexSet` 1D/2D In-Place Fast Path**: When the base slot holds a `Tensor` (`tag == 5`) of rank `1` or `2` and the indices and value are tagged `Int`s, stores `val >> 1` directly into `data_ptr[flat_idx]` in-place and returns the existing `Tensor` `RVal` pointer. Both caller and callee share `data_box`, so mutations inside helper functions returning `()` or `Int` are immediately visible to the caller.
  - **Direct Column Slice & Flat Bitwise Hadamard**: `:tensor-col-slice:` pre-allocates a 1D tensor via `:tensor-zeros:` (`OPT-004`) and fills it in-place; `EHadamard` (`xor`, `and`, `or`) operates directly across the flat `data_ptr` arrays of the two input tensors (`NCallBuiltin 90`).

### `OPT-006` — Direct Binary `sha256_raw` & Ephemeral Concatenation Fusion (`sha256_raw (a + b)`)
- **Location**: `lower_call_expr` in `src/main/ridgun/lib/compiler.ridgun` and `NCallBuiltin 36`, `NCallBuiltin 89` in `src/main/ridgun/lib/x86_64.ridgun`.
- **Problem Addressed**:
  1. `sha256_raw` (`NCallBuiltin 36`) previously delegated to `sha256_str` (`b_id = 21`), which copied the input into a heap `Vec<u8>`, formatted the 8 `u32` digest words into a 64-byte ASCII hex `String` via `core::fmt::write`, and then parsed the 64 ASCII hex characters back into 32 raw bytes.
  2. In HMAC-SHA256 and PBKDF2-HMAC-SHA256 (`sha256 raw (opad + (sha256 raw (ipad + u)))`), each iteration performed two heap string concatenations (`ipad + u` and `opad + inner`) and re-compressed the constant 64-byte `ipad` and `opad` blocks from scratch 1,200,000 times.
- **Transformation**:
  - **Direct Binary Digest (`NCallBuiltin 36`)**: Compresses full 64-byte blocks directly from the input `String` slice without copying, pads the final block (1–2 blocks, 64–128 bytes) on the stack, byte-swaps (`bswap`) the 8 `u32` state words `H[0..7]` directly into a 32-byte stack buffer, and wraps it with `rg_new_str(rsp, 32)`.
  - **Ephemeral Concatenation Fusion (`sha256_raw (a + b)` -> `NCallBuiltin 89`)**: When `compiler.ridgun` lowers `ECall "sha256_raw" [EBin OpAdd a b]`, it evaluates `a` and `b` into adjacent slots without calling `NBinOp 0` (`rg_str_concat`). When `len(a) == 64` (the standard 512-bit block size used by HMAC `ipad`/`opad`), `NCallBuiltin 89` checks a 2-slot midstate cache keyed by the 64 bytes of `a`, reusing the post-block-0 SHA-256 state `H[0..7]` and compressing only the tail `b` on the stack with zero intermediate heap allocations.

### `OPT-007` — Right-Associative List Cons Chain Fusion (`a:b:c:xs`)
- **Location**: `parse_add_loop`, `parse_colon_combine` in `src/main/ridgun/lib/parser.ridgun` and `check_binop` in `src/main/ridgun/lib/typecheck.ridgun`.
- **Pattern**: Right-associative list constructor chains `a:b:c:xs` and `a:b:c:[]` in expressions (symmetric with `(a:b:c:xs)` in pattern matching).
- **Transformation**: Rather than allocating $k$ intermediate 1-element lists and performing $k$ sequential list concatenations, `parse_colon_combine` folds contiguous `:` chains into a single prefix `EList [a, b, c]` concatenated once with `xs` (`EBin OpConcat (EList [a, b, c]) xs`), or directly into `EList [a, b, c]` when the tail is `[]`.

### `OPT-008` — Inline LLVM IR Register Fast-Paths (`NBinOp`, Slot Ops, 64-Bit `U64` Boxing, `str_char_at`)
- **Location**: `lower_call_expr` (`str_char_at` -> `NCallBuiltin 91`) in `src/main/ridgun/lib/compiler.ridgun` and `@__rg_fast_bin_op`, `@__rg_fast_clone_slot`, `@__rg_fast_store_slot`, `@__rg_fast_rebind_slot`, `@__rg_fast_cmm_drop_slot`, `@__rg_fast_drop_val`, `@__rg_fast_as_bool`, `@__rg_box_i64`, `@__rg_str_char_at_fast`, `@__rg_builtin_str_char_at` in `src/main/ridgun/lib/llvm.ridgun`.
- **Transformation**:
  1. **Register-Promoted `NBinOp` & Slot Fast-Paths**: Executes integer arithmetic/bitwise/rotate/comparison ops (`+`, `-`, `*`, `/`, `%`, `==`, `!=`, `>`, `<`, `>=`, `<=`, `and`, `or`, `xor`, `shl`, `shr`, `rotr` via `@llvm.fshr.i64`, `rotl` via `@llvm.fshl.i64`) and immediate slot loads/stores directly in LLVM IR, running `opt -O2` (SROA + Mem2Reg + CGSCC Inliner) before `llc -O2` so local slots `%frame[i]` and `%acc` are promoted to hardware registers (`2,000 x blamka p16` = 16,000 BlaMka G rounds in `13 ms`).
  2. **Full 64-Bit `U64` Heap Boxing (`@__rg_box_i64_slow`)**: Stores `-9223372036854775808` (`0x8000000000000000`) at offset 0 of the `RVal` buffer when boxing 64-bit integers with `bit 63 != bit 62` (`0x4000000000000000 .. 0xBFFFFFFFFFFFFFFF`), and unboxes heap `U64` operands in `@__rg_bin_op_u64_or_slow` and `@__rg_not_op` so `Tensor[U64 * ...]` supports all 64 bits without truncation.
  3. **Inline `str_char_at` Local Borrow (`NCallBuiltin 91`)**: When `str_char_at` is called on a local variable `s`, reads the byte directly from `%frame[s_slot]`'s `dptr` in LLVM IR (`@__rg_str_char_at_fast`) without cloning or dropping `s`.

### `OPT-009` — Unrolled Constant-Offset Frame Prologue/Epilogue (`SROA` Unlock) & Direct `NCallFn` Tensor Maps
- **Location**: `tensor_map_call_instr` in `src/main/ridgun/lib/compiler.ridgun` and `llvm_unroll_init_frame`, `llvm_unroll_clear_locals`, `llvm_unroll_epilogue`, `emit_llvm_fn`, `@__rg_tensor_index_*_slow` in `src/main/ridgun/lib/llvm.ridgun`.
- **Transformation**:
  1. Unrolls function prologue (`0..arity-1` from `%args`, `arity..num_slots-1` zeroed), `NClearLocals` (`<= 8` slots), and single-exit function epilogue (`epilogue_exit:`) into constant-offset `getelementptr` + `@__rg_fast_drop_val` calls for non-TCO functions with `num_slots <= 24`, and passes `i64` values by value to `@__rg_tensor_index_*_slow`. Because `ptr %frame` never escapes to external `.rt` functions, LLVM `SROA` splits `%frame` into individual SSA registers and `InstCombine` folds away `@__rg_fast_drop_val` on `0` or immediate `Int`/`Bool` values at compile time.
  2. Emits direct `NCallFn` instead of `NCallIndirect1` in `:tensor-map-rows-in:`, `:tensor-map-cols-in:`, and `:tensor-map-elems-in:` when the mapped function is a known top-level unary function, allowing LLVM's CGSCC inliner to inline the mapped body directly into the loop.

### `OPT-010` — `!invariant.load !0` on Immutable `Tensor` Metadata & `noalias` Buffer Allocation
- **Location**: `@__rg_adt_field_neg`, `@__rg_tensor_index_1d`, `@__rg_tensor_index_2d`, `@__rg_tensor_index_set_1d`, `@__rg_tensor_index_set_2d`, `llvm_runtime_declarations` in `src/main/ridgun/lib/llvm.ridgun`.
- **Transformation**: Annotates all loads of immutable `Tensor` metadata (`tag`, `shdr`, `dhdr`, `sptr`, `rk`, `d0`, `d1`, `dptr`, `len`) with `!invariant.load !0` and marks `@__rg_rt_alloc_buf` / `@__rg_rt_box_rc_vec` return pointers `noalias`. `opt -O2` (`EarlyCSE` / `GVN` / `LICM`) deduplicates and hoists all pointer indirections and tag/rank/bounds checks even across stores to `dptr[idx]`.

### `OPT-011` — Hardware `rep movsb`/`rep stosb`/`rep stosq` & Zero-Boxing Row/Col Slice & Set Built-ins (`NCallBuiltin 92..95`)
- **Location**: `lower_tensor_helper`, `lower_tensor_set_row_slots`, `lower_tensor_get_col_slots`, `lower_tensor_set_col_slots` in `src/main/ridgun/lib/compiler.ridgun` and `@__rg_memcpy`, `@__rg_memset`, `@__rg_builtin_tensor_fill`, `@__rg_builtin_tensor_row_slice`, `@__rg_builtin_tensor_set_row`, `@__rg_builtin_tensor_col_slice`, `@__rg_builtin_tensor_set_col` in `src/main/ridgun/lib/llvm.ridgun`.
- **Transformation**:
  1. Replaces byte-by-byte loops in `@__rg_memcpy` and `@__rg_memset` with `inlinehint` hardware `rep movsb` / `rep stosb` and uses `rep stosq` in `@__rg_builtin_tensor_fill`.
  2. Lowers 2D row slicing `m_(r,)` (`92`) and in-place row assignment `m_(r,) = v` (`93`) to contiguous `@__rg_memcpy` (`rep movsb` of `cols * 8` bytes, with zero heap allocations on `m_(r,) = v`), and lowers 2D column slicing `m_(,c)` (`94`) and in-place column assignment `m_(,c) = v` (`95`) to unboxed `i64` strided loops.

### `OPT-012` — SIMD-Vectorized Flat Hadamard (`+`, `-`, `*`, `and`, `or`, `xor`) & Cache-Friendly 2D `NEinsum` (`@__rg_fast_einsum`)
- **Location**: `lower_expr` (`EHadamard`) in `src/main/ridgun/lib/compiler.ridgun` and `@__rg_builtin_tensor_bitop`, `@__rg_fast_einsum` in `src/main/ridgun/lib/llvm.ridgun`.
- **Transformation**:
  1. Routes flat (`s1 == s2`) arithmetic Hadamard (`+`, `-`, `*`) as well as bitwise Hadamard (`and`, `or`, `xor`) to `@__rg_builtin_tensor_bitop` (`NCallBuiltin 90`) and hoists `switch i64 %op_id` outside the loop into 6 branch-free loops so `opt -O2` (`LoopVectorize`) emits AVX2/SSE2 SIMD instructions (`vpaddq`, `vpsubq`, `vpmullq`, `vpand`, `vpor`, `vpxor`).
  2. Executes 2D matrix multiplication (`A_ik @ B_kj` / `A_ij @ B_jk`) in `@__rg_fast_einsum` using cache-friendly unit-stride `i-k-j` loop order over unboxed `i64` buffers.

### `OPT-013` — Direct SSA Register Calling Convention (`@__rg_fn_{fid}_reg`) & Caller Frame Escape Elimination
- **Location**: `emit_llvm_fn`, `emit_llvm_instr` (`NCallFn`) in `src/main/ridgun/lib/llvm.ridgun`.
- **Problem Addressed**:
  1. Previously, every user function had a single entry signature `define i64 @__rg_fn_{fid}(ptr %args)`, and every direct call `NCallFn fid start_slot count` computed `%s = getelementptr [N x i64], ptr %frame, i64 0, i64 start_slot` and passed `ptr %s` to `@__rg_fn_{fid}(ptr %s)`.
  2. Passing a pointer into `%frame` to a function call caused LLVM's alias analysis to treat the caller's `%frame` array as **address-taken / escaped** across calls, preventing `SROA` / `Mem2Reg` from promoting caller local variables into SSA registers in non-leaf functions and forcing every argument pass through stack memory.
- **Transformation**:
  1. **Dual Entry Point (`@__rg_fn_{fid}_reg` + `@__rg_fn_{fid}` ABI wrapper)**: For every user function (`fid >= 5`) with `arity <= 8`, `llvm.ridgun` emits the implementation in `define i64 @__rg_fn_{fid}_reg(i64 %arg_0, ..., i64 %arg_{k-1})` (annotated with `inlinehint` for compact functions) and initializes `%frame[0..arity-1]` directly from the SSA register parameters `%arg_0 .. %arg_{k-1}`.
  2. **Indirect/Runtime Compatibility Wrapper**: `@__rg_fn_{fid}(ptr %args)` is emitted as a thin wrapper that loads `%av_0 .. %av_{k-1}` from `ptr %args`, zeroes `ptr %args[0..k-1]` (`store i64 0`, preserving the RMM move contract for indirect calls via `@__rg_page0`, `NCallIndirect1`, `NCallIndirect2`, and `spawn`), and calls `@__rg_fn_{fid}_reg(%av_0, ..., %av_{k-1})`.
  3. **Direct Register Calls at `NCallFn`**: When `NCallFn fid start_slot count` targets a user function with `fid >= 5` and `count <= 8` matching the function's arity, the caller loads `%av_0 .. %av_{count-1}` from `%frame[start_slot .. start_slot + count - 1]`, immediately zeroes those caller frame slots (`store i64 0, ptr %ap_i, align 8`), and calls `call i64 @__rg_fn_{fid}_reg(i64 %av_0, ...)`. Because `ptr %frame` never escapes to `NCallFn`, LLVM `SROA` promotes `%frame` to SSA registers across function calls and `CGSCC` inlines small helper functions directly into callers.

### `OPT-014` — AST-Level Higher-Order Function (`fold`, `map`, `filter`) Direct-Call Specialization
- **Location**: `specialize_hof_fndef_list` in `src/main/ridgun/lib/compiler.ridgun`.
- **Problem Addressed**: Standard list pipelines `xs map f -> filter p -> fold g init` previously lowered to runtime built-ins (`NCallBuiltin 4` / `5` / `6`) that invoked `f`, `p`, and `g` via indirect runtime dispatch (`NCallIndirect1` / `NCallIndirect2` through `@__rg_page0` and `ptr %args`) and allocated intermediate closures or list structures through generic runtime helpers.
- **Transformation**:
  - When `fold f init xs`, `map f xs`, or `filter p xs` is called where the first argument `f`/`p` is an `EVar fn_name` referencing a known top-level function (including lifted lambdas `__rg_lambda_*` after lambda lifting), `compiler.ridgun` synthesizes a specialized recursive helper function (`__rg_spec_fold_{id}`, `__rg_spec_map_{id}`, `__rg_spec_filter_{id}`) that invokes `fn_name` via a direct `ECall` and replaces the HOF call site with a direct call to the specialized helper.
  - Because the synthesized helper is a standard `FnDef`, it automatically benefits from `OPT-002` (self-TCO loop for `fold`), `OPT-003` (`RMM1` static last-use drops), `OPT-009` (unrolled frame `SROA`), and `OPT-013` (`@__rg_fn_{fid}_reg` register calling convention and cross-function inlining of `fn_name` into the loop).


### `OPT-015` — Inline Tail-Call Frame Copy & Epilogue for Small Frames
- **Location**: `emit_llvm_fn`, `emit_llvm_instr` (`NTailCall`, `NClearLocals`), `llvm_unroll_tco_copy` in `src/main/ridgun/lib/llvm.ridgun`.
- **Problem Addressed**: `OPT-009` unrolls the prologue and epilogue only for functions without a self tail call. A loop (`OPT-002`) still called `@__rg_rt_tco_copy` on every turn (a 256-byte buffer clear plus a drop loop) and `@__rg_rt_epilogue` on exit. Passing `ptr %frame` to these calls kept the whole frame in memory. An empty three-argument loop cost about 20 ns per turn.
- **Transformation**: For `fid >= 5`, `arity <= 8` and `num_slots <= 24`:
  1. The prologue stores the register arguments and zeroes the other slots one by one; the epilogue is `llvm_unroll_epilogue`.
  2. `NTailCall start arity` becomes, in this order: load and zero `%frame[start + i]` for each argument; load, zero and `@__rg_fast_drop_val` every slot `0 .. num_slots - 1`; store the arguments in `%frame[0 .. arity - 1]`. This is the order of effects of `@__rg_rt_tco_copy`.
  3. `NClearLocals` is unrolled up to 24 slots (was 8).
- **Effect**: no call takes `%frame`, so `SROA` turns the frame into SSA values and the loop body into register code: 1 000 000 turns of an empty loop take 3 ms instead of 20 ms.

### `OPT-016` — Direct Record Field Reads & Inline ADT Match/Field Fast Paths
- **Location**: `lower_field_read` (`lower_call_expr`) in `src/main/ridgun/lib/compiler.ridgun`; `@__rg_adt_field_fast`, `@__rg_match_adt_fast` in `src/main/ridgun/lib/llvm.ridgun`.
- **Problem Addressed**: `field r` called the accessor function. The caller cloned the record, the accessor read the field through the runtime and dropped the record: three runtime calls per read.
- **Transformation**:
  1. `field r` with `r` a local variable lowers to `NAdtField (slot of r) k`: the record stays in its slot (borrowed), only the field is cloned. Any other record expression is computed into a scratch slot, read, and dropped (`NCmmDropSlot`).
  2. LLVM: `NAdtField slot k` (k >= 0) calls `@__rg_adt_field_fast`: if the value is a heap ADT (tag 4) and `k` is below the field count, it reads the field word from the field vector and clones it with `@__rg_fast_clone_slot`; otherwise it calls `@__rg_rt_adt_field`.
  3. LLVM: `NMatchAdt slot off len arity` calls `@__rg_match_adt_fast`: tag 4, same constructor name length, same bytes (the name is a constant in `@__rg_rodata`, so the loop folds to immediate compares), same field count.
- **ADT layout used** (same as `@__rg_rt_adt_field` and `@__rg_rt_match_adt`): `i32` tag 4 at `+0`; constructor name header at `+8` (data pointer at `+8`, length at `+16`); field vector header at `+16` (data pointer at `+8`, length at `+16`, one 8-byte word per field).

### `OPT-017` — Deferred Parameter Move in Self Tail Calls
- **Location**: `tco_deferred_vars`, `lower_tco_args_deferred`, `lower_tco_deferred_moves` (`lower_tail_return_cmm`) in `src/main/ridgun/lib/compiler.ridgun`.
- **Problem Addressed**: `OPT-002` moves a parameter into its argument slot only when no later argument reads it. In `loop r (j + 1) (acc + field r)` the record `r` was cloned on every turn and the old copy dropped by the frame copy.
- **Transformation**: A parameter passed as a plain argument and read by a later argument is skipped in the first pass; the other arguments are computed (they read it from its own slot, and cannot move it: it is added to the scope variables); then it is moved into its argument slot. Only parameters qualify: they cannot be reassigned, so the value is the same at both points.

### `OPT-018` — Borrowed Pattern Parameters
- **Location**: `borrow_masks`, `fn_borrow_mask`, `lower_borrow_call`, `borrow_fn_instrs` in `src/main/ridgun/lib/compiler.ridgun`; `NPeekSlot`, `NForgetSlot` in `elf64.ridgun`, `llvm.ridgun`, `x86_64.ridgun`, `arm64.ridgun`.
- **Problem Addressed**: A small function that matches its record parameter (`get a (R a _ _) = a`) received a clone of the record and dropped it on return: two reference-count updates through the runtime per call.
- **Which parameters are borrowed**: parameter `i` of function `f` when every clause matches it with a pattern that only reads it: a constructor (not a typed-tensor or primitive wrapper pattern), a tuple, `[]`, a string, or `_`. The value is never bound to a name, so the body cannot return, store or pass it. `f` must also: have arity 1..20 and the same number of patterns in every clause, have no sequence binding, not call itself, not start with `__`, not be an overloadable operator, and not be in the dispatch set (function values, partial application, names used as strings, agents, entry points, show roots, every function of a library). Those are exactly the functions that are only called through `lower_direct_or_partial_call`. The bit mask is stored in the function arity map under the key `"#b " + name`.
- **Callee**: before every `NReturn` (and at the end of the instructions) it emits `NForgetSlot i` for each borrowed parameter: the slot is set to 0 without a drop, so the epilogue leaves the value alone. Argument slots are never in a `NClearLocals` range (those start at `arity`).
- **Caller**: arguments for owned parameters are computed as before. For a borrowed parameter:
  - a local variable is skipped in the first pass and copied as is (`NPeekSlot` then `NStoreSlot`) right before the call: no clone; the variable keeps ownership;
  - any other expression is computed into its argument slot, moved to a scratch slot `sp + count + i`, copied as is into the argument slot, and the scratch slot is dropped after the call (`NCmmDropSlot`; the result is parked in `sp + 2 * count` meanwhile).
  - The call itself zeroes the argument slots as before (`OPT-013` on LLVM; `@__rg_rt_init_frame` on x86-64 and ARM64), so the value is owned once.
- **Tail calls**: a function that any function calls in tail position never borrows (`borrow_tail_fns` adds those names to the excluded set: the last expression of a body, of a block, of every guard branch and of a `where` body). A borrowed call drops its scratch values after the call returns, so in tail position it would no longer be the last instruction, and the backend could not turn it into a jump. A call to a borrowing function inside the arguments of a tail call (`loop n (emit step acc)`) is not itself in tail position, so it may borrow; `lower_tco_arg_expr` lowers it with `lower_tco_borrow_call`, which moves owned arguments on their last use like any other call there. A local passed to a borrowed parameter of the same call counts as a later use, so it is never moved.
- **Incident (Solstice report 2026-11-10, fixed in 0.9.51)**: until 0.9.50 `lower_tco_arg_expr` lowered calls to borrowing functions without moves. In `scan n i acc = scan n (first step) (emit step acc)` with `emit (_, h) acc = acc :: [h]`, `acc` was cloned on every round, so `acc :: [h]` copied the whole list: 8 000 rounds took 835 ms, 100 000 several minutes. Now 100 000 rounds take about 110 ms. Regression test: `tests/cases/perf/append_through_borrowing_callee.ridgun`.
- **Incident (2026-11-08, fixed in 0.9.46)**: the first version had no tail-call exclusion. In the lexer, `lex loop at` calls `lex step (lex one tok ...) src len rev_acc` in tail position and `lex step` calls `lex loop at` back. The call became a real call with a drop after it. Each pending `lex loop at` frame kept `rev_acc` alive, so `[tok] :: rev_acc` copied the whole list on every token, and memory grew quadratically: 1 000 rounds 24 MB, 4 000 rounds 321 MB. The self-built compiler passed 7 GB in 3 s on `check`; uncapped runs crashed the machine. Regression test: `tests/cases/functions/tail_call_to_pattern_parameter_function.ridgun`.
- **Effect**: 1 000 000 calls of `get a r` in a loop: 6 ms (62 ms on 0.9.45). x86-64: 80 ms (124 ms).

### `OPT-019` — Tail Calls Between Different Functions
- **Location**: `is direct call target`, `lower tail return expr`, `guards have direct tail call`, `unit tail call ok`, `add unit marks`, `fill tail call fns` in `src/main/ridgun/lib/compiler.ridgun`; `NTailCallFn` in `elf64.ridgun`, `llvm.ridgun` (`llvm tail teardown`, `emit llvm fn list linked`), `x86_64.ridgun` (`x86 tail fn shift`), `arm64.ridgun`.
- **Problem Addressed**: Only self tail calls reused the frame (`OPT-002`). A call to another function in tail position was `NCallFn` then `NReturn`, and the epilogue ran after the call, so it was a real call. Two functions calling each other kept one frame per round: `loop tuple` <-> `step tuple` used 74 MB at 300 000 rounds and crashed at 2 000 000 (SIGSEGV on x86-64, SIGILL on LLVM). Guards without a self call were lowered as an ordinary expression, and a unit function added `()` after its last call, so neither kept the call in tail position.
- **Transformation**:
  1. Compiler: a direct call (`is direct call target`: a user function with all its arguments, not a builtin, constructor, agent, tensor helper, local function value or borrowing callee) in tail position computes its arguments into `sp .. sp + count - 1`, drops the scope variables it uses, and emits `NTailCallFn fid sp count slots`. Guards with such a call in a branch take `lower tail guards cmm`. A unit function keeps its last call unwrapped when the callee is also a unit function (marked `"#u " + name` in the arity map). `slots` (the callee's frame size) is filled in after all functions are lowered (`fill tail call fns`). A borrowing function empties its borrowed slots before `NTailCallFn` as before `NReturn`.
  2. LLVM: the `_reg` entry points use `tailcc`. `NTailCallFn` loads and zeroes the argument slots, drops every frame slot (unrolled up to 24 slots, else `@__rg_rt_epilogue`), then `tail call tailcc @__rg_fn_{fid}_reg(...)` and `ret` of its result. The targets get `weak_odr` linkage: without it `opt` proved that a unit callee always returns 0, returned the constant instead of the call's result, and the call stopped being a tail call. More than 8 arguments: a call and a return.
  3. x86-64: `rg_tco_copy` moves the arguments to slots 0..count-1 and drops the rest; the arguments move to the base of a frame of the callee's size (`rsp = rbp - frame size`, moved downward or upward by the size difference); slots `count .. slots - 1` are zeroed (`rep stosq`); then a jump to the callee's body after its 42-byte prologue. Size: `68 + 16 * count` bytes. More than 32 arguments: a call and a return.
  4. ARM64: a call and a return (not implemented yet; FR-COMP-004 §3).
- **Effect**: 3 000 000 rounds of `loop tuple` <-> `step tuple`: 8.6 MB on both backends (crash before). The self-built compiler's peak memory on `check compiler.ridgun` fell from 308 MB to 216 MB, because the lexer's and parser's mutual tail calls no longer keep frames. Regression test: `tests/cases/functions/mutual_tail_calls_3m.ridgun`.

### `OPT-020` — In-Place String Append in Tail Calls
- **Location**: `str add fact` in `src/main/ridgun/lib/typecheck.ridgun`; the `EBin OpAdd` clause of `lower tco arg expr` and `str add chain` in `src/main/ridgun/lib/compiler.ridgun`; `str_append` (builtin 121) in the runtime extension (`docs/etc/runtime_ext.md`).
- **Problem Addressed**: `rep x n acc = rep x (n - 1) (acc + x)` cloned `acc` and the runtime's `+` always made a new String of the exact size, so each round copied the whole String: 100 000 rounds took 2.3 s (TASK-0068, found while fixing the Solstice report of 2026-11-10).
- **Transformation**:
  1. The type checker records `fn|$v|S` for every `v + r` whose result is a String (the same channel as the tensor element facts; `$` keeps the keys apart).
  2. In a tail position (`lower tco arg expr`: an argument of a self tail call, or a tail return), `l + r` where the leftmost operand of the `+` chain `l` is such a variable is lowered as: `l` with moves (its last use is moved, `NMoveSlot`), `r`, then `NCallBuiltin 121 sp 2`; on `0` it falls back to `NMoveSlot (sp + 1)`, `NBinOp 0 sp` (the usual `+`).
  3. Builtin 121: when both values are Strings and the left String's header (`{capacity, data, length, rc}`) has rc 1, it copies the right bytes after the left ones, growing the buffer to `max(2 * capacity, needed, 32)` when needed (the old buffer is freed by dropping a String built around it), and returns the left String. Otherwise it returns 0 and leaves both slots alone.
- **Safety**: a String that another variable, list or record still holds has rc > 1 (a clone adds one), so it is never changed. A local that is read again after the call is cloned, not moved. Borrowed parameters (`OPT-018`) are never bound to a name, so they cannot be the left operand.
- **Effect**: 100 000 rounds of `rep "a" n ""`: 2.3 s -> 3 ms on both backends; 200 rounds of a 1 MB String stay under 64 MB. Regression test: `tests/cases/perf/string_append_in_tail_call.ridgun`.

### Rule: tail calls stay last
Applies to every new or changed optimization.
- A call in tail position (the last expression of a function body, a block, a guard branch or a `where` body) must stay the last instruction before the return. Then the backend reuses the frame: `NTailCall` for self calls (`OPT-002`), `NTailCallFn` for calls to other functions (`OPT-019`).
- An optimization must not emit code after such a call (drops, moves, stores of values that are read later). If it needs work after the call, it must skip calls in tail position, as `OPT-018` does with `borrow_tail_fns`.
- Losing a tail call does more than grow the stack. The pending frames keep their values alive, so reference counts stay above 1 and in-place updates (`::`, `+` on strings, tensor writes) start copying. Memory can then grow quadratically.
- Every compiler, bootstrap stage and test run must be capped (`ulimit -v` 3-4 GB plus `timeout`). Before trusting a new compiler, compare the stage-2 peak memory on `check` and on a self-build with the installed compiler.

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
- **Required adaptation when unboxing slots**: Attach a static `SlotDropKind` (`NoDropScalar` vs. `ManagedRVal`) to each slot in `NativeFn` (`compiler.ridgun` -> `llvm.ridgun`). For `NoDropScalar` slots:
  - Omit `@__rg_fast_drop_val` in `llvm_unroll_epilogue` (`OPT-009`), `llvm_unroll_clear_locals`, and `NCmmDropSlot` (`OPT-003`).
  - Use plain `store i64` instead of `@__rg_fast_store_slot` / `@__rg_fast_rebind_slot` (`OPT-008`).
  - Box/unbox at polymorphic (`A..Z`) or heap container (`List`, `Tuple`, ADT field) boundaries.

### 2. Call-Boundary Ownership Transfer Contract (`OPT-002`, `OPT-009`, `OPT-013`)
Under the current `RMM1` / `RMM2` lowering in `compiler.ridgun`:
1. **Caller Preparation (`lower_call_args`)**: Before emitting `NCallFn fid start_slot count`, the caller evaluates each argument into `%frame[start_slot + i]`. If an argument is a local variable at its static last use (`RMM1`), the caller uses `NMoveSlot` (moving the pointer and zeroing the source local slot); otherwise it uses `NCloneSlot` (incrementing the heap refcount by `+1` for heap `RVal`s).
2. **Ownership Transfer on Call (`OPT-013`)**: The callee takes ownership of the `count` values placed in `start_slot .. start_slot + count - 1` and stores them in its own parameter slots `%frame[0 .. arity - 1]`.
   - In **indirect calls** via `@__rg_fn_{fid}(ptr %args)` (or `llvm_unroll_init_frame` when reading `ptr %args`), the callee zeroes `args[0..arity-1]` (`store i64 0, ptr %ap_i`) as it transfers the words into its own frame.
   - In **direct register calls** via `@__rg_fn_{fid}_reg(i64 %arg_0, ...)` (`OPT-013`), the **caller** loads `%av_i = %frame[start_slot + i]` and **immediately zeroes `%frame[start_slot + i]` (`store i64 0`)** before calling `@__rg_fn_{fid}_reg`.
   - **Why zeroing caller `start_slot + i` is mandatory**: If the caller did not zero `%frame[start_slot + i]` after passing `%av_i` by value into `@__rg_fn_{fid}_reg`, both the callee's epilogue (which drops `%frame[0..arity-1]`) AND the caller's epilogue (or subsequent `NStoreSlot` overwriting `%frame[start_slot + i]`) would drop the same heap `RVal` pointer, causing a double-free.
3. **Callee Return & Epilogue (`OPT-009`)**: Before jumping to `epilogue_exit:`, the return expression's slot is moved into `%acc` (`NMoveSlot` zeroes that slot in `%frame`), and `llvm_unroll_epilogue` drops all remaining non-zero slots in `%frame[0..num_slots-1]`.

**Exception (`OPT-018`)**: parameters that every clause only matches with a pattern are caller-owned borrows. The callee empties their slots with `NForgetSlot` before it returns, and the caller passes local variables with `NPeekSlot` (no clone). Points 1 to 3 below are what that implementation does for those parameters.

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

