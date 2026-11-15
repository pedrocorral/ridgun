# Ridgun runtime contract

This page states the contract between compiled Ridgun code and the Ridgun runtime: what compiled code may assume, and what the runtime must provide. It is the input for a runtime written from scratch in target-neutral LLVM IR (ADR-0013, TASK-0088).

The page uses only readable sources: Ridgun source, comments, LLVM IR text in `llvm.ridgun`, and the docs. No machine code was decoded. Every fact has a source as `file:line`. **UNKNOWN** marks a fact that the sources do not decide; the text says what is missing. **CONFLICT** marks two sources that disagree.

## 0. Sources and short names

| Short name | Path |
|---|---|
| `x86_64.ridgun` | `src/main/ridgun/lib/x86_64.ridgun` (x86-64 encoder and runtime image) |
| `llvm.ridgun` | `src/main/ridgun/lib/llvm.ridgun` (LLVM IR backend) |
| `elf64.ridgun` | `src/main/ridgun/lib/elf64.ridgun` (NIR types, ELF image) |
| `compiler.ridgun` | `src/main/ridgun/lib/compiler.ridgun` (lowering to NIR) |
| `arm64.ridgun` | `src/main/ridgun/lib/arm64.ridgun` (ARM64 encoder) |
| `wasm.ridgun@HEAD` | `src/main/ridgun/lib/wasm.ridgun` as committed at `58b9b5b` (the working copy is being rewritten; its lines differ) |
| `parser.ridgun` | `src/main/ridgun/lib/parser.ridgun` |
| `runtime_ext.md` | `docs/etc/runtime_ext.md` (runtime extension `rtx.c`, ids >= 100) |
| `runtime_windows.md` | `docs/etc/runtime_windows.md` |
| `gentensor.md` | `docs/etc/gentensor.md` |
| `compiler_optimizations.md` | `docs/etc/compiler_optimizations.md` |
| `cmm_architecture.md` | `docs/etc/cmm_architecture.md` |
| `spec.md` | `docs/lang/spec.md` |
| `FR-COMP-00n`, `FR-VM-00n` | `docs/requirements/functional/compiler/FR-COMP-00n-*.md`, `docs/requirements/functional/vm/FR-VM-00n-*.md` |

Sources that are **not** authoritative for this contract:

- `docs/etc/low_level_ridgun_runtime_design.md` is an old study. It uses 16-byte slots and a different slot numbering. The code does not follow it.
- `docs/etc/parallelism.md` describes a VM green-thread model. It does not describe the native runtime.
- The slot comments in `x86_64.ridgun` give wrong names for slots 40 to 48 (see section 9).

## 1. Values

Every Ridgun value is one 64-bit word.

| Value | Word | Source |
|---|---|---|
| `Int` n (fits in 63 bits) | `2n + 1` (low bit 1) | `wasm.ridgun@HEAD:13-14`; `runtime_ext.md:122`; `x86_64.ridgun:306-307` (`NLoadImmInt` loads `n*2+1`) |
| `Bool` False | `2` | `wasm.ridgun@HEAD:14`; `compiler.ridgun:2788` |
| `Bool` True | `6` | `wasm.ridgun@HEAD:14`; `compiler.ridgun:2786` |
| Unit `()` | `0` | `wasm.ridgun@HEAD:14`; `compiler.ridgun:2790` |
| Empty or moved slot | `0` (same word as Unit) | `x86_64.ridgun:678` (`cmm_move` sets `*slot = 0`); `runtime_ext.md:15` |
| Heap value | a nonzero pointer with the low 3 bits 0 | `runtime_ext.md:122-123`; `runtime_ext.md:224-227` (`is_ptr`) |

Rules that follow from these sources:

- A word is a heap pointer when it is nonzero and `(w & 7) == 0` (`runtime_ext.md:224-227`).
- Clone and drop skip `0` and immediates. They act only on heap pointers (`llvm.ridgun:105`, helper block `h1b`).
- An `Int` outside the tagged range (about ±2^62) is a heap box. The compiler builds wide literals with `NBinOp` (`compiler.ridgun:1641-1662`). `box_i64` keeps a value that fits in 63 bits as a tagged word. Otherwise it calls `box_rval` with `[0x8000000000000000, v, 0]` (`llvm.ridgun:104`).
- A routine that reads an `Int` argument accepts a tagged `Int` or a heap value whose i32 tag at +0 is 0; the payload is then the word at +8 (`runtime_ext.md:224-227`, `int_arg`).
- The runtime builtin 13 (`str_to_int`) tags its result without boxing, so values with |n| >= 2^62 lose bit 62. The compiler works around this with a Ridgun helper (`compiler.ridgun:4378-4380`).
- A `Real` is a heap value `[0, bits, 0]` with the IEEE-754 bits at +8 (`x86_64.ridgun:382-387`; `llvm.ridgun:733-748`).
- So a heap value with i32 tag 0 is either a `Real` (full word 0 at +0) or a boxed 64-bit integer (full word `0x8000000000000000` at +0). This reading combines `llvm.ridgun:104` (`not_op` tests the U64 header `0x8000...`) and `x86_64.ridgun:391` (`NIsGen`: Real has tag 0).
- `Char`: **UNKNOWN**. The sources show `char_from_code` (builtin 11, `compiler.ridgun:1515`) and `:char-zero:` lowered to `char_from_code 0` (`compiler.ridgun:2838`), but no source states the word of a `Char`.
- Function values: a named function used as a value is a `String` that holds the function name. The dispatchers match that name (`compiler.ridgun:4159-4163`, `compiler.ridgun:4215-4236`).
- Closures: a closure is a 2-tuple `(name, captured values list)` (`compiler.ridgun:2136-2141`, `compiler.ridgun:4163`).

## 2. Heap objects

### 2.1 The RVal box

Every heap value is an *RVal* of three words `[tag, w1, w2]`, made by `box_rval` (`llvm.ridgun:92` declares `box_rval(ptr) -> i64`; `runtime_ext.md:257-260` builds `{tag, a, b}` and calls it). The i32 at +0 is the tag (`runtime_ext.md:123`).

| Tag (i32 at +0) | Kind | Layout | Source |
|---|---|---|---|
| 0, word `0` | `Real` | +8 IEEE-754 bits, +16 0 | `x86_64.ridgun:382-387` |
| 0, word `0x8000000000000000` | boxed 64-bit integer | +8 the value, +16 0 | `llvm.ridgun:104` |
| 1 | `String` | +8 pointer to an RcVec header; header +8 data, +16 length (bytes) | `runtime_ext.md:123-124` |
| 2 | `List` (also 1-D GenTensor) | +8 RcVec header (64-bit values); +16 start index | `runtime_ext.md:125`; `llvm.ridgun:751-755`; `gentensor.md:7` |
| 4 | ADT value | +8 constructor name, String-like header (+8 data, +16 length); +16 fields header (+8 data, +16 length = arity) | `llvm.ridgun:104` (`match_adt_fast`) |
| 5 | numeric `Tensor` | +8 shape header (+8 dims pointer, +16 rank); +16 data header (+8 pointer, +16 length) of raw 64-bit words | `runtime_ext.md:126`; `llvm.ridgun:109-112` |
| 5 | `Tensor[U8]` | numeric tensor with shape `[W]`; word 0 rank k, words 1..k dims, then packed bytes, zero padded | `runtime_ext.md:129-133`; `llvm.ridgun:789-796` |
| ? | `Tuple` | **UNKNOWN**: no readable source states the tag or layout. `make_tuple` returns a "Tuple RVal" (`x86_64.ridgun:723`). | — |

- A 2-D GenTensor is a list of row lists; each row has its own RcVec (`gentensor.md:8`).
- A `List` RVal made by the GenTensor helpers is `[2, vec header, 0]`; the start index at +16 is 0 there (`llvm.ridgun:767`).
- Record values: records are ADTs with field getter functions (`compiler.ridgun:4584`, `lower field getter`). Record update goes through `NAdtSet` (rt 33) (`compiler.ridgun:2855-2857`, `x86_64.ridgun:416`).

### 2.2 The RcVec header

An RcVec header is four words `{cap, data, len, rc}`. `box_rc_vec(ptr) -> ptr` makes one from a 3-word template `{cap, data, len}` (`llvm.ridgun:92`; `runtime_ext.md:253-255`, `vec_new` passes `{len, buf, len}`).

- `runtime_ext.md:706` says: "A String's header is {capacity, data, length, rc}". The rc is `h[3]`, at +24.
- TASK-0068 says the `::` path checks rc at +24 and a clone adds one to rc (`docs/road-map/completed/2026-11/TASK-0068-*.md:29`).
- An RcVec buffer is freed by wrapping it as `{cap, data, 0}` in a String RVal and dropping that (`runtime_ext.md:705-738`).

**CONFLICT / UNKNOWN (reference count location).** `compiler_optimizations.md:219` says an RVal has its refcount at offset -8. The rtx and TASK-0068 sources put rc in the RcVec header at +24. No readable source says which counter `clone_slot` (rt 5) and `drop_val` (rt 6) change for each tag, or whether both counters exist.

### 2.3 Allocator

- `alloc_buf(i64 n) -> noalias ptr` gives a buffer of n bytes (`llvm.ridgun:92`; `runtime_ext.md:145`, `RT_ALLOC_BUF`).
- `alloc_str(ptr src, i64 n) -> i64` makes a String from n bytes (`llvm.ridgun:92`; `runtime_ext.md:148`).
- `pop_i64(ptr) -> i64` exists (`llvm.ridgun:92`); `tensor_fill` uses it to read slot values (`llvm.ridgun:113`). Its exact meaning is **UNKNOWN**.
- `drop_slot(ptr)` clears a slot and drops its value (`llvm.ridgun:92`; same rule as `runtime_ext.md:230-234`).
- The x86 runtime region `0x403000..0x403800` is a "Bump-arena mmap slab allocator, region quota & RVal box alloc" (`x86_64.ridgun:970`).
- Allocator internals are **UNKNOWN**: slab sizes, free lists, `mmap` sizes, whether freed blocks are reused, alignment beyond 8, and out-of-memory behaviour. Only the region comment above exists.
- The image reserves 131072 bytes of zeroed memory after the file content (`elf64.ridgun:123-126`; `llvm.ridgun:647`, `.bss` + 131072). What the runtime keeps there is **UNKNOWN**.

### 2.4 Memory management (RMM1 and RMM2)

RMM2 is reference counting:

- `clone_slot` (rt 5) is "RMM2 +1" (`x86_64.ridgun:668`).
- `drop_val` (rt 6) is "RMM2 -1 & child cascade" (`x86_64.ridgun:673`). The recursive drop of children lives in `0x401800..0x402000` (`x86_64.ridgun:955`).
- `rebind_slot` (rt 9) is "RMM2 +1 new before -1 old" (`x86_64.ridgun:688`).

RMM1 is static last-use drop decided by the compiler:

- `cmm_drop_slot` (rt 10) is the "RMM1 static last-use drop" and updates the cond-freed and cond-spared counters (`x86_64.ridgun:693`).
- The compiler emits `rg_cmm_drop` when a variable has no live peers, and `rg_cmm_drop_unless` with the list of live peers otherwise (`cmm_architecture.md:104`).
- The full rules are in `cmm_architecture.md:7-95` and `FR-COMP-002:105-149`.

Counters (builtins 5, 6, 7) and the pointer test (49):

| Builtin | Meaning | Source |
|---|---|---|
| 5 `cmm_live_blocks` | current number of live tracked heap allocations | `cmm_architecture.md:106` |
| 7 `cmm_cond_freed` | total guards where `ptr(v) != ptr(keep)` freed the other branch | `cmm_architecture.md:107` |
| 6 `cmm_cond_spared` | total guards where `ptr(v) == ptr(keep)` spared the shared block | `cmm_architecture.md:108` |
| 49 `cmm_same_ptr` | `True` if two values point to the same heap allocation | `cmm_architecture.md:109` |

- Test data: a list literal counts as 1 live block. The trace test expects `(2,1,1,0,2,1)` for `True` and `(2,2,1,0,2,1)` for `False` (`src/test/ridgun/test core language.ridgun:80-133`, `:552-557`).
- **UNKNOWN**: which allocations count as "tracked blocks" (Strings? boxed Ints? RcVec headers as separate blocks?), and when exactly `cmm_drop_slot` increments each counter. Only the one-line descriptions above exist.

## 3. Frames and the accumulator

### 3.1 The accumulator

- Each NIR instruction leaves its result in the accumulator (`rax` on x86-64; an `alloca` in LLVM) (`llvm.ridgun:522-575`, function shape; `wasm.ridgun@HEAD:61-62`, local 2 is the accumulator).
- `NStoreSlot s` stores the accumulator into slot s through rt 8 (`x86_64.ridgun:329`).

### 3.2 Frames

- A function frame is an array of `num_slots` 64-bit words. Slot k is at `frame + 8k` (`x86_64.ridgun:33-43`; `wasm.ridgun@HEAD:63`).
- On x86-64 the frame is on the stack. Its size is `((num_slots + 1) / 2) * 16` bytes (`x86_64.ridgun:287-288`).
- Each `NativeFn` has `fid`, `name`, `arity`, `num_slots` and its instructions (`elf64.ridgun:11`).
- The x86-64 prologue is 42 bytes. It calls rt 1 with `rdx = arity` and `rcx = num_slots` (`x86_64.ridgun:290-293`). `NTailCall` jumps to `fn + 42` to skip it (`x86_64.ridgun:504`).

### 3.3 Calls and ownership

- `NCallFn fid start count`: the caller puts the arguments in its slots `start .. start+arity-1` and passes `rdi = &slot[start]` (`x86_64.ridgun:454-456`). The x86-64 encoder ignores `count`; the callee's prologue gives the arity.
- `init_frame` (rt 1) moves the arguments into the new frame, clears them at the source, and zeroes the other slots (`wasm.ridgun@HEAD:290-291`; `llvm.ridgun:522-575`, unrolled form "args zeroed at source").
- So the callee owns its arguments (`compiler_optimizations.md:228-240`). The caller passes a value it keeps with `NCloneSlot`, and a value it gives away with `NMoveSlot` (same source).
- OPT-018 borrowed parameters use `NPeekSlot` / `NForgetSlot`, which are inline load and inline store of 0 with no refcount change (`x86_64.ridgun:323-326`; `compiler_optimizations.md:228-240`).
- `NReturn` calls `epilogue` (rt 2) with the frame, `num_slots` and the accumulator. The epilogue drops every slot and returns the result (`x86_64.ridgun:516-518`; `wasm.ridgun@HEAD:299`).
- LLVM: a call to `fid >= 5` with at most 8 arguments uses a `_reg` variant with `tailcc` (`llvm.ridgun:258-504`, emit rules). The caller zeroes its argument slots for `_reg` calls (`compiler_optimizations.md:228-240`).
- Tail calls: `tco_copy` (rt 3) drops the slots that are not arguments, then moves the arguments down to slots `0..arity-1` (`wasm.ridgun@HEAD:303-304`). `NTailCallFn` handles up to 32 arguments on x86-64 (`x86_64.ridgun:506-527`). The limits are 8 parameters on LLVM and 32 on x86-64 (`FR-COMP-004:17-40`).

## 4. Runtime entries

### 4.1 Slot table and symbols

- x86-64 code calls slot k through a jump table at `0x401000 + 8k` (`x86_64.ridgun:159-160`, `x86 call rt id` targets `4198400 + id*8`).
- The jump table entry k jumps to the address `x86 rt slot target k` (`x86_64.ridgun:573-629`).
- The LLVM linker script gives each `@__rg_rt_*` symbol the same address as the x86 slot target (`llvm.ridgun:649-651`). The LLVM backend links the x86 runtime image as section `.rg_rt` at `0x401000` (`llvm.ridgun:647`). `memcpy` and `memset` resolve to `__rg_memcpy` and `__rg_memset` (`llvm.ridgun:651`).
- ARM64 uses the same slot numbers (`arm64.ridgun:396-509`).
- The wasm backend at HEAD numbers its runtime functions 0..55 as the native slots, 56..63 for instructions that native code does inline, and 64..66 for heap entry points (`wasm.ridgun@HEAD:30-35`).

In the tables below: "Registers" are the x86-64 System V argument registers. "Args" are listed in order. The result is in `rax` (x86-64) or the LLVM return value.

### 4.2 Frame and memory entries (slots 0..10)

| Slot | LLVM declaration | Registers | NIR instruction | Meaning | Source |
|---|---|---|---|---|---|
| 0 | `_start` (linker script) | — | program entry | ELF entry: argc/argv setup, call `main` (section 7) | `x86_64.ridgun:632`, `:950`; `llvm.ridgun:647` |
| 1 | `void @__rg_rt_init_frame(ptr, ptr, i64, i64)` | rdi frame, rsi args, rdx arity, rcx num_slots | function prologue | move args into frame, clear the source, zero the other slots | `llvm.ridgun:89`; `x86_64.ridgun:648`, `:290-293`; `wasm.ridgun@HEAD:290-291` |
| 2 | `i64 @__rg_rt_epilogue(ptr, i64, i64)` | rdi frame, rsi num_slots, rdx result | `NReturn` | drop every slot; return the result | `llvm.ridgun:89`; `x86_64.ridgun:653`, `:516-518`; `wasm.ridgun@HEAD:299` |
| 3 | `void @__rg_rt_tco_copy(ptr, i64, i64, i64)` | rdi frame, rsi start, rdx arity, rcx num_slots | `NTailCall`, `NTailCallFn` | drop non-argument slots; move args to slots 0.. | `llvm.ridgun:89`; `x86_64.ridgun:658`, `:504-527`; `wasm.ridgun@HEAD:303-304` |
| 4 | `void @__rg_rt_clear_locals(ptr, i64, i64)` | rdi frame, rsi start, rdx end | `NClearLocals start end` | clear slots `start..end-1` | `llvm.ridgun:89`; `x86_64.ridgun:663`, `:337`; `wasm.ridgun@HEAD:315` |
| 5 | `i64 @__rg_rt_clone_slot(i64)` | rdi value | `NCloneSlot s` (rdi = slot value) | one more reference; returns the same word | `llvm.ridgun:89`; `x86_64.ridgun:668`, `:321`; `wasm.ridgun@HEAD:319` |
| 6 | `@__rg_rt_drop_val(i64)` | rdi value | `NDropVal` | one reference less; free and cascade to children at zero | `llvm.ridgun:89`; `x86_64.ridgun:673`, `:335`; `wasm.ridgun@HEAD:323` |
| 7 | `i64 @__rg_rt_cmm_move(ptr)` | rdi slot address | `NMoveSlot s` | return `*slot`, set `*slot = 0` | `llvm.ridgun:89`; `x86_64.ridgun:678`, `:327`; `wasm.ridgun@HEAD:327` |
| 8 | `@__rg_rt_store_slot(ptr, i64)` | rdi slot address, rsi new value (from acc) | `NStoreSlot s` | store the new value, then drop the old one | `llvm.ridgun:89`; `x86_64.ridgun:683`, `:329`; `wasm.ridgun@HEAD:331`; `llvm.ridgun:105` (`fast_store_slot`) |
| 9 | `@__rg_rt_rebind_slot(ptr, i64)` | rdi slot address, rsi new value | `NRebindSlot s` | store the new value; drop the old one as rt 10 does | `llvm.ridgun:89`; `x86_64.ridgun:688`, `:331`; `wasm.ridgun@HEAD:335`; `llvm.ridgun:105` |
| 10 | `@__rg_rt_cmm_drop_slot(ptr)` | rdi slot address | `NCmmDropSlot s` | clear the slot and drop its value (RMM1); update counters | `llvm.ridgun:89`; `x86_64.ridgun:693`, `:333`; `wasm.ridgun@HEAD:339` |

The return types of slots 6, 8, 9 and 10 are not visible in the summary of `llvm.ridgun:89`; the x86 callers ignore `rax` after them. Treat their result as unused.

### 4.3 Constructors and literals (slots 11..19)

| Slot | LLVM declaration | Registers | NIR instruction | Meaning | Source |
|---|---|---|---|---|---|
| 11 | `@__rg_rt_load_real_lit(ptr, i64)` | rdi rodata text, rsi length | `NLoadRealLit off len` | parse the decimal text into a Real RVal | `llvm.ridgun:90`; `x86_64.ridgun:698`, `:310` |
| 12 | `@__rg_rt_load_str_lit(ptr, i64)` | rdi rodata bytes, rsi length | `NLoadStrLit off len` | new String from the bytes | `llvm.ridgun:90`; `x86_64.ridgun:703`, `:312` |
| 13 | `@__rg_rt_load_adt0(ptr, i64)` | rdi constructor name, rsi length | `NLoadAdt0` | 0-ary ADT value; `-2` loads `Linux` (rodata +5, len 5), `-1` loads rodata +22, len 6 (`X86_64`) | `llvm.ridgun:90`; `x86_64.ridgun:708`, `:314-320`; `compiler.ridgun:969-975` |
| 14 | `@__rg_rt_make_adt(ptr, i64, ptr, i64)` | rdi name, rsi name length, rdx slots, rcx arity | `NMakeAdt` | ADT value from `arity` slots | `llvm.ridgun:90`; `x86_64.ridgun:713`, `:424` |
| 15 | `@__rg_rt_make_list(ptr, i64)` | rdi slots, rsi count | `NMakeList s n` | List of n slot values | `llvm.ridgun:90`; `x86_64.ridgun:718`, `:418` |
| 16 | `@__rg_rt_make_tuple(ptr, i64)` | rdi slots, rsi count | `NMakeTuple s n` | Tuple of n slot values | `llvm.ridgun:90`; `x86_64.ridgun:723`, `:420` |
| 17 | `@__rg_rt_make_tensor(ptr, i64)` | rdi slots, rsi count | `NMakeTensor s n` | numeric tensor; nested elements are flattened (helper at `0x4050d9`) | `llvm.ridgun:90`; `x86_64.ridgun:728-733`, `:422` |
| 18 | `@__rg_rt_str_interp(ptr, i64)` | rdi slots, rsi count | `NStrInterp s n` | String made of the formatted parts | `llvm.ridgun:90`; `x86_64.ridgun:738`, `:428`; `compiler.ridgun:2784` |
| 19 | `@__rg_rt_pack_seq(ptr, i64)` | rdi frame, rsi arity | `NPackSeq arity` | List of the frame's sequence-bound arguments | `llvm.ridgun:90`; `x86_64.ridgun:743`, `:380`; `compiler.ridgun:3790` |

- Do slots 14..18 consume their slot arguments (clear them)? **UNKNOWN**. The lowering calls `NClearLocals` after some uses but not after all; no source states the rule.
- The exact slots that `pack_seq` packs (from which slot index to `arity`) are **UNKNOWN**.
- LLVM builds empty lists and 1-element lists and 2-tuples inline (`llvm.ridgun:105`: `make_empty_list`, `make_list_1`, `make_tuple_2`).

### 4.4 Tests and access (slots 20..34)

All match entries return `0` or `1` (not a Bool word) (`x86_64.ridgun:748-803`).

| Slot | LLVM declaration | Registers | NIR instruction | Meaning | Source |
|---|---|---|---|---|---|
| 20 | `i64 @__rg_rt_as_bool(i64)` | rdi value | `NAsBool` | 1 for True, else 0; drops the value | `llvm.ridgun:90`; `x86_64.ridgun:748`, `:408`; `wasm.ridgun@HEAD:343` |
| 21 | `@__rg_rt_match_int(i64, i64)` | rdi value, rsi n | `NMatchInt` | 1 when value is the tagged n | `llvm.ridgun:91`; `x86_64.ridgun:753`, `:339`; `wasm.ridgun@HEAD:347` |
| 22 | `@__rg_rt_match_real(i64, ptr, i64)` | rdi value, rsi text, rdx length | `NMatchReal` | 1 when value equals the Real literal | `llvm.ridgun:91`; `x86_64.ridgun:758`, `:341` |
| 23 | `@__rg_rt_match_str(i64, ptr, i64)` | rdi value, rsi bytes, rdx length | `NMatchStr` | 1 when value is a String with these bytes | `llvm.ridgun:91`; `x86_64.ridgun:763`, `:343` |
| 24 | `@__rg_rt_match_bool(i64, i64)` | rdi value, rsi b | `NMatchBool` | 1 when value is True for b ≠ 0, False for b = 0 | `llvm.ridgun:91`; `x86_64.ridgun:768`, `:345`; `wasm.ridgun@HEAD:351` |
| 25 | `@__rg_rt_match_empty(i64)` | rdi value | `NMatchEmpty` | 1 for an empty list | `llvm.ridgun:91`; `x86_64.ridgun:773`, `:347` |
| 26 | `@__rg_rt_match_nonempty(i64)` | rdi value | `NMatchNonEmpty` | 1 for a non-empty list | `llvm.ridgun:91`; `x86_64.ridgun:778`, `:349` |
| 27 | `@__rg_rt_list_head(i64)` | rdi value | `NListHead` | the first element | `llvm.ridgun:91`; `x86_64.ridgun:783`, `:365` |
| 28 | `@__rg_rt_list_tail(i64)` | rdi value | `NListTail` | the list without its first element | `llvm.ridgun:91`; `x86_64.ridgun:788`, `:367` |
| 29 | `@__rg_rt_match_tuple(i64, i64)` | rdi value, rsi arity | `NMatchTuple` | 1 for a tuple of this arity | `llvm.ridgun:91`; `x86_64.ridgun:793`, `:351` |
| 30 | `@__rg_rt_tuple_get(i64, i64)` | rdi value, rsi index | `NTupleGet` | element at index | `llvm.ridgun:91`; `x86_64.ridgun:798`, `:369` |
| 31 | `@__rg_rt_match_adt(i64, ptr, i64, i64)` | rdi value, rsi name, rdx length, rcx arity | `NMatchAdt` (the native backends inline arity -1..-5; wasm32 sends every arity here) | 1 for this constructor and arity; a negative arity tests a primitive type: -1 Int, -2 Bool, -3 String (heap tag word 1), -4 Real (heap tag word 0), -5 numeric tensor (heap tag word 5) | `llvm.ridgun:92`; `x86_64.ridgun:803`, `:353-363` |
| 32 | `@__rg_rt_adt_field(i64, i64)` | rdi value, rsi index | `NAdtField` (index not -1, -2, <= -10) | field at index | `llvm.ridgun:92`; `x86_64.ridgun:808`, `:371-379` |
| 33 | `@__rg_rt_adt_set(ptr, i64, i64)` | rdi record slot address, rsi index, rdx new value | `NAdtSet` | updated ADT value | `llvm.ridgun:92`; `x86_64.ridgun:813`, `:416` |
| 34 | `@__rg_rt_bool_inv(i64)` | rdi value | `NNot` (non-Int) | the other Bool | `llvm.ridgun:92`; `x86_64.ridgun:823`, `:410`; `wasm.ridgun@HEAD:355` |

Inline forms that the new runtime does not need to provide, but must keep compatible with:

- `NMatchAdt` arity -1..-5 are inline checks on x86 (`x86_64.ridgun:353-362`). Their meaning per arity is **UNKNOWN** from readable source.
- `NAdtField -1`: String length (header +16). `-2`: the length at +16 of the header at +16. `<= -10`: tensor dimension `-10-idx` from the shape (`llvm.ridgun:104`, `adt_field_neg`; `compiler.ridgun:2829-2830`).
- `NNot` on an `Int` is `w xor -2`; on a boxed U64 it unboxes, inverts and reboxes (`llvm.ridgun:104`, `not_op`).

Ownership and errors:

- Does `list_head`, `list_tail`, `tuple_get` or `adt_field` return a clone (+1) or a borrowed word? The LLVM fast path `adt_field_fast` returns a clone of the field (`llvm.ridgun:104`). For the other entries this is **UNKNOWN**.
- Behaviour of rt 27, 28, 30, 32 on a wrong kind of value or an empty list is **UNKNOWN**.
- `adt_set`: whether it mutates in place when rc is 1 is **UNKNOWN**.

### 4.5 Output, operators, tensors (slots 35..42)

| Slot | LLVM declaration | Registers | NIR instruction | Meaning | Source |
|---|---|---|---|---|---|
| 35 | `@__rg_rt_out(i64)` | rdi value | `NOut` | write the value; return 0 | `llvm.ridgun:92`; `x86_64.ridgun:828`, `:412` |
| 36 | `@__rg_rt_echo(ptr, i64)` | rdi slots, rsi count | `NEcho s n` | write the n formatted values; return 0 | `llvm.ridgun:92`; `x86_64.ridgun:833`, `:426`; `compiler.ridgun:2876` |
| 37 | `@__rg_rt_bin_op(i64, ptr, i64)` | rdi op, rsi lhs slot address, rdx rhs (acc) | `NBinOp op s` | binary operator (section 6) | `llvm.ridgun:92`; `x86_64.ridgun:838-848`, `:414` |
| 38 | `@__rg_rt_index(ptr, ptr, i64)` | see source | `NIndex` | Tensor or List read | `llvm.ridgun:92`; `x86_64.ridgun:861`, `:430-435` |
| 39 | `@__rg_rt_index_set(ptr, ptr, i64, i64)` | see source | `NIndexSet` | in-place tensor write | `llvm.ridgun:92`; `x86_64.ridgun:866`, `:436-441` |
| 40 | `@__rg_rt_seq_select(i64, ptr, i64)` | rdi value (acc), rsi mask text, rdx length | `NSeqSelect off len` | select elements by a sequence mask such as `"-+-"` | `llvm.ridgun:92`, `:650`; `x86_64.ridgun:442`; `compiler.ridgun:2924` |
| 41 | `@__rg_rt_einsum(ptr, i64, ptr, i64)` | rdi slots, rsi count, rdx spec, rcx spec length | `NEinsum s n off len` | Einstein summation on Int tensors | `llvm.ridgun:92`, `:651`; `x86_64.ridgun:446`; `compiler.ridgun:2897` |
| 42 | `@__rg_rt_hadamard(i64, ptr, i64, ptr, i64)` | rdi op, rsi lhs slot address, rdx rhs (acc), rcx subscripts, r8 length | `NHadamard op s off len` | broadcasting element-wise operator | `llvm.ridgun:92`, `:651`; `x86_64.ridgun:448`; `compiler.ridgun:2907` |

- `NIndex` with base -1 or -2 (borrowed base) clones the base into a stack area first (`x86_64.ridgun:48-55`). LLVM has fast 1-D and 2-D paths and falls back to rt 38 after a bounds check (`llvm.ridgun:109-112`).
- An index outside the shape writes `runtime error: tensor index out of range` and exits with status 1 through builtin 24 (`x86_64.ridgun:142-147`; `llvm.ridgun:733-748`; `gentensor.md:17`).
- `NIndexSet` has 1-D and 2-D in-place fast paths for an Int or tag-0 payload and returns the base (`x86_64.ridgun:105-116`; `llvm.ridgun:109-112`). A Real value is stored as its bits (`x86_64.ridgun:64-69`).
- The exact register arguments of rt 38 and rt 39 are **UNKNOWN** from the readable parts of `x86_64.ridgun:430-441`; only the LLVM types are known.
- `NEinsumReal` does not call the runtime; on x86 it gives 0 (`x86_64.ridgun:444-445`). LLVM has a Real fast path for 2-D `"ab,bc"`; its slow path returns 0 (`llvm.ridgun:118`).
- The full einsum spec grammar, the `seq_select` mask grammar, and the hadamard broadcast rules are **UNKNOWN** from runtime sources. The compiler only shows the inputs (`compiler.ridgun:2890-2924`).
- `hadamard` op ids: the compiler passes `binop id` (`compiler.ridgun:2907`). Bitwise ops and same-subscript `+ - *` never reach rt 42; they go to builtin 90 (`compiler.ridgun:2899-2901`).

### 4.6 Regions (slots 43..48)

| Slot | LLVM declaration | Registers | NIR instruction | Meaning | Source |
|---|---|---|---|---|---|
| 43..46 | none | — | none | no NIR instruction calls them; no LLVM symbol | `llvm.ridgun:649-651`; `x86_64.ridgun:295-518` |
| 47 | `@__rg_rt_enter_region()` | none | `NEnterRegion` | enter a `with region` block | `llvm.ridgun:92`, `:651`; `x86_64.ridgun:450`; `arm64.ridgun:396-509` |
| 48 | `@__rg_rt_exit_region(i64, i64)` | rdi quota, rsi block value (acc) | `NExitRegion quota` | leave the block; returns the block result | `llvm.ridgun:92`, `:651`; `x86_64.ridgun:452-453`; `arm64.ridgun:396-509` ("returns block result in X1") |

- The compiler lowers `with region` as `NEnterRegion`, the body, then `NExitRegion quota` (`compiler.ridgun:2950-2953`).
- `spec.md:1187` says `with region 64_KB do` sets a lexical byte quota.
- **UNKNOWN**: what happens when the quota is exceeded, whether allocations inside the region come from a separate arena, and what "O(1) arena teardown" (the old comment at `x86_64.ridgun:901`) means for values that escape the block.

### 4.7 Slots 49..52

No NIR instruction calls slots 49..52, and no LLVM symbol names them (`x86_64.ridgun:295-518`; `llvm.ridgun:649-651`). ARM64 names them "shared" entries (`arm64.ridgun:396-509`). The new runtime may leave them out unless TASK-0088 says otherwise.

### 4.8 Calls and builtins (slots 53..55)

| Slot | LLVM declaration | Registers | NIR instruction | Meaning | Source |
|---|---|---|---|---|---|
| 53 | `@__rg_rt_call_indirect1(i64, ptr)` | rdi function value, rsi argument slot address | `NCallIndirect1` | call a function value with one argument through the spawn dispatcher (fid 2) | `llvm.ridgun:92`; `x86_64.ridgun:994`, `:500`; `arm64.ridgun:585` (loads the function at `0x400088`) |
| 54 | `@__rg_rt_call_indirect2(i64, ptr)` | rdi function value, rsi start slot address | `NCallIndirect2` | call a function value with two arguments through the call2 dispatcher (fid 3) | `llvm.ridgun:92`; `x86_64.ridgun:999`, `:502`; `arm64.ridgun:590` (`0x400090`) |
| 55 | `@__rg_rt_builtin(i64, ptr, i64)` | rdi id, rsi slots, rdx count | `NCallBuiltin id s n` (ids < 70 without a helper) | builtin dispatch (section 5) | `llvm.ridgun:92`; `x86_64.ridgun:1024-1059`, `:457-499` |

- How rt 53 and rt 54 build the frame for the dispatcher (which slots receive the name and the arguments) is **UNKNOWN** from readable source. The dispatchers expect: spawn slot 0 = name, slot 1 = argument (`compiler.ridgun:4159-4195`); call2 slot 0 = name, slot 1 = first argument, slot 2 = rest (`compiler.ridgun:4210-4236`).

### 4.9 Other symbols with fixed addresses

| Symbol | Address | Signature | Use | Source |
|---|---|---|---|---|
| `@__rg_rt_pal_dispatch` | 4286080 (`0x416680`) | `(i64, ptr, i64)` | builtins 70..99 not done inline | `llvm.ridgun:92`, `:651`; `x86_64.ridgun:1099`; `runtime_ext.md:151`, `:158` |
| `@__rg_rt_ext` | 4289168 (`0x417290`) | `(i64, ptr, i64)` | builtins >= 100 (`rg_rtx`) | `llvm.ridgun:92`, `:651`; `x86_64.ridgun:1115-1121` |
| `@__rg_rt_drop_slot` | 4200437 | `void (ptr)` | clear a slot, drop its value | `llvm.ridgun:92`, `:651` |
| `@__rg_rt_alloc_buf` | 4205566 | `noalias ptr (i64)` | raw buffer | `llvm.ridgun:92`, `:651`; `runtime_ext.md:145` |
| `@__rg_rt_box_rc_vec` | 4208821 | `ptr (ptr)` | RcVec header from `{cap, data, len}` | `llvm.ridgun:92`, `:651`; `runtime_ext.md:146` |
| `@__rg_rt_box_rval` | 4209847 | `i64 (ptr)` | RVal from `{tag, w1, w2}` | `llvm.ridgun:92`, `:651`; `runtime_ext.md:147` |
| `@__rg_rt_pop_i64` | 4212364 | `i64 (ptr)` | **UNKNOWN** meaning (see 2.3) | `llvm.ridgun:92`, `:651` |
| `@__rg_rt_alloc_str` | 4212489 | `i64 (ptr, i64)` | String from bytes | `llvm.ridgun:92`, `:651`; `runtime_ext.md:148` |
| `RT_DROP_VAL` | 4214519 | `(i64)` | same as slot 6 target | `runtime_ext.md:149`; `x86_64.ridgun:579` |
| `RT_BUILTIN` | 4241227 | `(i64, ptr, i64)` | same as slot 55 target | `runtime_ext.md:150`; `x86_64.ridgun:628` |

### 4.10 Wasm-only entries (HEAD)

At HEAD the wasm backend names runtime functions 56..66 for work the native encoders do inline (`wasm.ridgun@HEAD:30-35`, `:97-180`):

| k | Instruction | Native behaviour | Source |
|---|---|---|---|
| 56 | `NIsList` | True (6) when heap tag is 2, else False (2) | `x86_64.ridgun:388`; `gentensor.md:28` |
| 57 | `NIsGen` | True when the value is not a number (tagged Int, boxed Int, tag-0 Real) | `x86_64.ridgun:391`; `gentensor.md:27` |
| 58 | `NListSet` | store acc in a list slot, drop the old element (calls rt 6) | `x86_64.ridgun:406`; `gentensor.md:28` |
| 59 | `NListGet` | clone of the element; out of range stops the program | `x86_64.ridgun:397`, `:404`; `llvm.ridgun:783-786` |
| 60 | `NSortBy` | sort by keys; different lengths give `runtime error: sort by: the lists have different lengths` | `x86_64.ridgun:400-403`; `llvm.ridgun:764` |
| 61 | `NGtConv slot mode` | modes 0..4 per `gentensor.md:29-33`; mode 5 is `__rg_gt_repeat` | `gentensor.md:29-33`; `compiler.ridgun:2824` |
| 62 | `NRealFromBits` | Real RVal `[0, bits, 0]` from an Int | `x86_64.ridgun:382-387`; `llvm.ridgun:733-748` |
| 63 | `NRealToBits` | the Int bits of a Real | `x86_64.ridgun:382-387`; `llvm.ridgun:733-748` |
| 64, 65 | — | heap clone and heap drop (called by rt 5 and rt 6) | `wasm.ridgun@HEAD:319-323` |
| 66 | — | heap path of `bin_op` | `wasm.ridgun@HEAD:359-360` |

## 5. Builtins

### 5.1 Dispatch

`NCallBuiltin id s n` passes `n` argument slots starting at slot `s`. The backends route it as follows (`x86_64.ridgun:457-499`; `llvm.ridgun:258-504`):

| Id | Route | Source |
|---|---|---|
| 1, 32 (count 0 or 1), 33, 50 | channel routine under the channel lock | `x86_64.ridgun:118-140`; `llvm.ridgun:119` |
| 32 (blocking) | loop on 33 until the result matches `Ok`/1, then take field 0 | `llvm.ridgun:119` |
| 10, 40 | LLVM fast paths for String length and byte at index; slow path rt 55 | `llvm.ridgun:108` |
| 36 | `sha256_raw`: builtin 21 gives hex, then the hex is converted to 32 raw bytes | `x86_64.ridgun:71-76`; `llvm.ridgun:115` |
| 57, 58, 59 | job routines | `llvm.ridgun:121`; `gentensor.md:566-591` |
| 86, 87 | inline `pipe` and `wait4` | `llvm.ridgun:116` |
| 88 | tensor fill | `x86_64.ridgun:57-62`; `llvm.ridgun:113` |
| 89..99 | own routines | `x86_64.ridgun:1210-1260`; `gentensor.md:566-591` |
| 105, 106 | LLVM U8 fast paths | `llvm.ridgun:789-796` |
| other >= 100 | `@__rg_rt_ext` at `0x417290` | `x86_64.ridgun:1115-1121` |
| other 70..99 | `@__rg_rt_pal_dispatch` at `0x416680` | `x86_64.ridgun:1099`; `runtime_ext.md:151`, `:158` |
| other < 70 | rt 55 with rdi = id, rsi = slots, rdx = count | `x86_64.ridgun:457-499` |

### 5.2 Ownership of argument slots

- For ids >= 100: the routine consumes its slots. It drops each owned value and sets every slot to 0. A borrowed slot (filled by `NPeekSlot`) is set to 0 and not dropped (`runtime_ext.md:15`).
- LLVM helpers follow the same rule where visible: `builtin_str_len` drops its argument (`llvm.ridgun:108`); `tensor_bitop` drops slots 0 and 1 (`llvm.ridgun:114`); the sha256 helpers drop their slot (`llvm.ridgun:115`).
- For ids 0..62 dispatched through rt 55: whether every builtin consumes its slots, and how a builtin knows that a slot is borrowed, is **UNKNOWN**.

### 5.3 Ids 0..62 (rt 55)

"Signature" is the Ridgun type from the requirement, when one exists.

| Id | Name(s) | Signature / result | Source (name) | Source (meaning) |
|---|---|---|---|---|
| 0 | `cli_args` | the program arguments; exact type **UNKNOWN** | `compiler.ridgun:1482`, `:1503` | — |
| 1 | `new_mailbox`, `mailbox`, `new_channel`, `channel` | new channel | `compiler.ridgun:1483-1486`, `:1504-1507` | `spec.md:960-990` |
| 2 | `sys_getcwd` | `=> String` | `compiler.ridgun:1487` | `FR-VM-002:34` |
| 3 | `sys_getuid` | `=> Int` | `compiler.ridgun:1488` | `spec.md:1167` (list only) |
| 4 | `sys_getgid` | `=> Int` | `compiler.ridgun:1489` | `spec.md:1167` (list only) |
| 5 | `cmm_live_blocks` | `=> Int` | `compiler.ridgun:1497` | `cmm_architecture.md:106` |
| 6 | `cmm_cond_spared` | `=> Int` | `compiler.ridgun:1498` | `cmm_architecture.md:108` |
| 7 | `cmm_cond_freed` | `=> Int` | `compiler.ridgun:1499` | `cmm_architecture.md:107` |
| 10 | `str_len` | `String => Int` | `compiler.ridgun:1514` | `llvm.ridgun:108` |
| 11 | `char_from_code` | `Int => Char` | `compiler.ridgun:1515` | **UNKNOWN** |
| 12 | `int_to_str` | `Int => String` | `compiler.ridgun:1516` | **UNKNOWN** |
| 13 | `str_to_int` | `String => Int` (no boxing, see section 1) | `compiler.ridgun:1517` | `compiler.ridgun:4378-4380` |
| 14 | `read_file` | `String => String`, verbatim | `compiler.ridgun:1518` | `FR-VM-001:24-28` |
| 15 | `load_rg_source` | `String => String`, with `import` splicing | `compiler.ridgun:1519` | `FR-VM-001:28` |
| 17 | `shell_exec` | **UNKNOWN** | `compiler.ridgun:1521` | `x86_64.ridgun:1019` (fork/execve/wait4) |
| 18 | `list_dir` | `String => [String]`, sorted, no `.`/`..` | `compiler.ridgun:1522` | `FR-VM-002:20` |
| 19 | `file_lstat` | `String => (Bool, String, Int, Int, Int, String, String, Int, String)` | `compiler.ridgun:1523` | `FR-VM-002:21` |
| 20 | `sha256_file` | `String => String` (64 hex chars) | `compiler.ridgun:1524` | `FR-VM-002:23` |
| 21 | `sha256_str` | `String => String` (hex) | `compiler.ridgun:1525` | `x86_64.ridgun:1014`, `:71-76` |
| 22 | `sys_chdir` | `String => Int` | `compiler.ridgun:1528` | `FR-VM-002:33` |
| 23 | `sys_getenv` | `String => String` (`""` if unset) | `compiler.ridgun:1529` | `FR-VM-002:35` |
| 24 | `sys_exit` | `Int => ()`, exits with the code | `compiler.ridgun:1530` | `FR-VM-002:37`; `runtime_ext.md:245-251` |
| 25 | `sys_username` | `Int => String` | `compiler.ridgun:1531` | `FR-VM-002:41` |
| 26 | `sys_lookup_uid_gid` | `String => (Int, Int)`, `(-1, -1)` if not found | `compiler.ridgun:1532` | `FR-VM-002:43` |
| 27 | `sys_user_groups` | `String => [String]` | `compiler.ridgun:1533` | `FR-VM-002:42` |
| 28 | `sys_setresgid` | `Int => Int` | `compiler.ridgun:1534` | `FR-VM-002:44` |
| 29 | `sys_setgroups` | `[Int] => Int` | `compiler.ridgun:1535` | `FR-VM-002:44` |
| 30 | `sys_setresuid` | `Int => Int` | `compiler.ridgun:1536` | `FR-VM-002:44` |
| 31 | `sys_read_pass` | `String => String`, echo off on `/dev/tty` | `compiler.ridgun:1537` | `FR-VM-002:46` |
| 32 | `receive_from`, `chan_recv` | blocking receive (count 0/1: non-blocking form) | `compiler.ridgun:1538-1539` | `llvm.ridgun:119` |
| 33 | `try_receive_from`, `chan_try_recv` | `Ok v` or another constructor | `compiler.ridgun:1540-1541` | `llvm.ridgun:119` |
| 35 | `new_bounded_channel` | **UNKNOWN** | `compiler.ridgun:1542` | — |
| 36 | `sha256_raw`, `sha256_bytes` | 32-byte String | `compiler.ridgun:1526-1527` | `spec.md:1163` |
| 40 | `str_char_at` | `String Int => Int` (byte; out of range gives the raw word -1) | `compiler.ridgun:1543` | `llvm.ridgun:108` |
| 41 | `str_concat` | **UNKNOWN** | `compiler.ridgun:1544` | — |
| 42 | `str_starts_with` | **UNKNOWN** (presumably Bool; not stated) | `compiler.ridgun:1545` | — |
| 43 | `str_contains` | **UNKNOWN** | `compiler.ridgun:1546` | — |
| 45 | `write_file` | **UNKNOWN** | `compiler.ridgun:1548` | `x86_64.ridgun:1004` |
| 46 | `sys_mkdir` | `String Int => Int` | `compiler.ridgun:1549` | `FR-VM-002:24` |
| 47 | `sys_chmod` | `String Int => Int` | `compiler.ridgun:1550` | `FR-VM-002:25` |
| 48 | `sys_setenv` | `String String => Int` | `compiler.ridgun:1551` | `FR-VM-002:36` |
| 49 | `cmm_same_ptr` | `A A => Bool` | `compiler.ridgun:1552` | `cmm_architecture.md:109` |
| 50 | `send_through`, `chan_send` | send (count 2) | `compiler.ridgun:1553-1554` | `llvm.ridgun:119` |
| 51 | `receive_from_timeout` | **UNKNOWN** | `compiler.ridgun:1555` | — |
| 53 | `map`, `seq_map` | sequential map | `compiler.ridgun:1556-1557` | `FR-COMP-001`; `spec.md:1146` |
| 54 | `\|\|map`, `par_map` | parallel map; also `"__rg_par_eval__"` for `\|\|` DAGs | `compiler.ridgun:1558-1559`, `:2938`, `:3111` | `x86_64.ridgun:1009` |
| 55 | `filter`, `seq_filter` | sequential filter | `compiler.ridgun:1560-1561` | `FR-COMP-001` |
| 56 | `\|\|filter`, `par_filter` | parallel filter | `compiler.ridgun:1562-1563` | `x86_64.ridgun:1009` |
| 57 | job spawn | see 7.4 | `compiler.ridgun:2157-2329` | `llvm.ridgun:121` |
| 58 | job poll | see 7.4 | `llvm.ridgun:121` | `llvm.ridgun:121` |
| 59 | job await | see 7.4 | `compiler.ridgun:2157-2329` | `llvm.ridgun:121` |
| 60 | `str_slice` | **UNKNOWN** | `compiler.ridgun:1564` | — |
| 61 | `fold` | sequential left fold `acc = f acc x` | `compiler.ridgun:1565`, `:2485` | `spec.md:1150` |
| 62 | `sys_exec` | `String [String] [String] => Int`, no shell | `compiler.ridgun:1566` | `FR-VM-002:32` |

- Ids 8, 9, 16, 34, 37, 38, 39, 44, 52 have no name in `builtin call id` (`compiler.ridgun:1502-1607`). The x86 comment lists more builtins in slot 55 (split, replace, trim, case, symlink, unlink) (`x86_64.ridgun:1029-1044`); their ids are **UNKNOWN**.
- How `map`, `filter` and `fold` call the function argument (rt 53 / rt 54 or the dispatchers directly) is **UNKNOWN**.
- The thread pool of `||map` and `||filter` uses work stealing, clones and futexes (`x86_64.ridgun:1009`). Its size and ordering guarantees are **UNKNOWN**.
- Error behaviour of ids 0..62 on bad input is **UNKNOWN**, except that `sys_exit` ends the process (`FR-VM-002:37`).

### 5.4 PAL ids 70..87

`FR-COMP-007:58-77` and `spec.md:1174-1187` give the semantics.

| Id | Name | Arguments → result | Source |
|---|---|---|---|
| 70 | `sys_getpid` | → Int | `compiler.ridgun:1490`, `:1582` |
| 72 | `sys_deadline_ms` | → active deadline, or -1 | `compiler.ridgun:1494`; `spec.md:1185` |
| 73 | `sys_remaining_ms` | → remaining ms, or -1 | `compiler.ridgun:1495`; `spec.md:1185`; `runtime_ext.md:750-751` |
| 74 | `sys_sleep_ms` | ms → `()` | `compiler.ridgun:1595`; `spec.md:1184` |
| 75 | `sys_open_mode` | path, `"r"`/`"w"`/`"a"`/`"rw"`/`"w+"`/`"a+"` → fd or `-errno` | `compiler.ridgun:1596`; `spec.md:1175` |
| 76 | `sys_open` | path, flags (0 read, 1 write, 2 rdwr, 64 create, 512 trunc, 1024 append, 2048 nonblock), mode → fd or `-errno` | `compiler.ridgun:1597`; `spec.md:1176` |
| 77 | `sys_close` | fd → 0 or `-errno` | `compiler.ridgun:1598`; `spec.md:1177` |
| 78 | `sys_read_fd` | fd, max → String | `compiler.ridgun:1599`; `spec.md:1178` |
| 79 | `sys_write_fd` | fd, String → bytes or `-errno` | `compiler.ridgun:1600`; `spec.md:1179` |
| 80 | `sys_poll` | fd, events (1 in, 4 out), timeout → revents, 0, or `-errno`; timeout < 0 inside `with timeout` uses the remaining time | `compiler.ridgun:1601`; `spec.md:1181` |
| 81 | `sys_terminate` | pid, force → Int | `compiler.ridgun:1602`; `spec.md:1182` |
| 82 | `sys_kill` | pid, signal → 0 or `-errno` | `compiler.ridgun:1603`; `spec.md:1182` |
| 83 | `sys_call` | nr, a1..a6 → result | `compiler.ridgun:1604`; `spec.md:1183` |
| 84 | timeout enter | value of `"__rg_timeout_ms__"` context; starts a deadline | `compiler.ridgun:2945-2949`; `parser.ridgun:793-807` |
| 85 | timeout exit | the block value → the block value; restores the previous deadline | `compiler.ridgun:2945-2949`; `spec.md:1187` |
| 86 | `sys_pipe` | → tuple of two fds (syscall 22) | `compiler.ridgun:1496`; `llvm.ridgun:116` |
| 87 | `sys_waitpid` | pid → code (`signal + 128` or exit status), pid -1 on error (wait4, 61) | `compiler.ridgun:1606`; `llvm.ridgun:116`; `FR-COMP-007:58-77` |

- Id 71 has no name (`compiler.ridgun:1481-1607`).
- **UNKNOWN**: where the deadline is stored (per thread or global), the exact argument slots of 84, and the result of 81.

### 5.5 Ids 88..99 (own routines)

| Id | Meaning | Source |
|---|---|---|
| 88 | tensor fill: numeric tensor of any rank from `[v, d1, ..., dn]` (shape and data from `alloc_buf`, `box_rc_vec`, then `box_rval [5, shape, data]`) | `llvm.ridgun:113`; `x86_64.ridgun:57-62`; `compiler.ridgun:1840`, `:1853` |
| 89 | `sha256 raw (a + b)`: concatenate with rt 37 op 0, then the builtin 36 sequence | `gentensor.md:572`, `:589`; `x86_64.ridgun:78-91`; `compiler.ridgun:2725` |
| 90 | element-wise `+ - *`, `and or xor`, tensor clone (op id in slot 2; ops 0, 1, 2, 11, 12, else xor) | `gentensor.md:573`; `llvm.ridgun:114`; `compiler.ridgun:1858`, `:2017` |
| 91 | `str char at s i` for a local `s` | `gentensor.md:574`; `compiler.ridgun:2730` |
| 92 | `m_(r,)` row slice | `gentensor.md:575`; `compiler.ridgun:1913` |
| 93 | write of `m_(r,)` | `gentensor.md:576`; `compiler.ridgun:1872` |
| 94 | `m_(,c)` column slice | `gentensor.md:577`; `compiler.ridgun:1882` |
| 95 | write of `m_(,c)` | `gentensor.md:578`; `compiler.ridgun:1877` |
| 96 | thread id (syscall 186), tagged | `gentensor.md:579`; `llvm.ridgun:119` |
| 97 | send `(tid, v)` | `gentensor.md:580`; `llvm.ridgun:119` |
| 98 | receive this thread's reply: drains up to 1024 messages, keeps the one with its own tid, sends the others back; returns `(3, payload)` or 0 | `gentensor.md:581`; `llvm.ridgun:119` |
| 99 | take this thread's job from a list | `gentensor.md:582`; `llvm.ridgun:120` |

### 5.6 Extension ids 100..135

All go to `rg_rtx(id, slots, count)` at `0x417290` (`x86_64.ridgun:1115-1118`). The full table with slots and results is `runtime_ext.md:20-54`. Names are in `compiler.ridgun:1520-1592`. Ids used directly by the lowering: 104 (`compiler.ridgun:1897`), 105 (`:4895`, `:4901`), 106 (`:5195`), 107 (`:3625`), 110 (`:2848`), 111 (`:2851`), 116 (`:2742`), 117 (`:2721`), 121 (`:3226`).

| Id | Meaning (short) | Borrowed slot |
|---|---|---|
| 100, 101, 102 | monotonic ns, wall ms, monotonic ms | — |
| 103 | CRC-32 of a byte range | — |
| 104 | new `Tensor[U8]` filled with a value | — |
| 105 | read a U8 element | t |
| 106 | write a U8 element, returns unit (0) | t |
| 107 | rank or dimension k | t |
| 108, 109 | String ↔ `Tensor[U8]` | — |
| 110, 111 | `Tensor[U8]` → `[Int]`; → word tensor for `echo` | — |
| 112, 113 | read bytes, write bytes | — |
| 114, 115 | `read`/`write` into or from a tensor range | — |
| 116 | `sys call` with buffers | — |
| 117, 118 | sha256 of a `Tensor[U8]` as String; digest as `Tensor[U8 * 32]` | — |
| 119 | `Tensor[U8]` from a list of 0..255 | — |
| 120 | `execve` | — |
| 121 | in-place String append when header rc is 1, else 0 and slots unchanged | — |
| 122, 123, 124 | unlink, rmdir, rename | — |
| 125..135 | network (`FR-VM-003`) | — |

Source for every row: `runtime_ext.md:20-54`.

- Errors in the extension write a message to stderr and call builtin 24 with `Int 1` (exit status 1) (`runtime_ext.md:245-251`).
- Messages: U8 out of range, tensor index out of range, crc32 range, write bytes element, byte range (`runtime_ext.md:239-243`).

## 6. Binary operators

### 6.1 Operator ids

`binop id` (`compiler.ridgun:1443-1464`):

| Id | Op | Id | Op | Id | Op |
|---|---|---|---|---|---|
| 0 | `+` | 7 | `>` | 14 | concat |
| 1 | `-` | 8 | `<` | 15 | flat join |
| 2 | `*` | 9 | `>=` | 16 | matmul |
| 3 | `/` | 10 | `<=` | 17 | shift left |
| 4 | `%` | 11 | `and` | 18 | shift right |
| 5 | `==` | 12 | `or` | 19 | rotate right |
| 6 | `!=` | 13 | `xor` | 20 | rotate left |

`NBinOp op s`: the left operand is in slot s, the right operand is the accumulator. rt 37 gets `rdi = op`, `rsi = &slot[s]`, `rdx = acc` (`x86_64.ridgun:414`; `compiler.ridgun:2815-2819`).

### 6.2 Int semantics

Both operands tagged `Int` (`llvm.ridgun:106`, `exec_int_op`; `llvm.ridgun:107`, `fast_bin_op`):

| Ops | Result |
|---|---|
| 0, 1, 2 | 64-bit wrap-around arithmetic, then `box_i64` (heap box when the result does not fit in 63 bits) |
| 3, 4 | division and remainder; divisor 0 gives 0; `MIN / -1` gives `MIN`, `MIN % -1` gives 0 |
| 5..10 | comparison; True 6 or False 2 |
| 11, 12, 13 | bitwise and, or, xor |
| 17, 18 | shift by `b & 63`; shift right is logical |
| 19, 20 | rotate right (`fshr`), rotate left (`fshl`) |
| other | 0 |

- Ops 14, 15, 16 never take the Int fast path; LLVM sends them to `bin_op_u64_or_slow` (`llvm.ridgun:369-371`).
- The wasm HEAD path sends rotations, concat, flat join and matmul to the heap path (`wasm.ridgun@HEAD:378-383`). **CONFLICT** with LLVM, which rotates inline. The LLVM behaviour is the reference.
- Whether `/` and `%` round toward zero (LLVM `sdiv`/`srem`) or toward negative infinity is **UNKNOWN** from the summary of `llvm.ridgun:106`; read that line before implementing.

### 6.3 Bool semantics

- Both operands Bool and op in {11, 12, 13, 5, 6}: done inline. The xor result is or-ed with 2 to stay a valid Bool (`llvm.ridgun:107`).
- `and` and `or` in source short-circuit in the compiler. Only a non-short-circuit case reaches `NBinOp 11` or `12` (`compiler.ridgun:2799-2814`).

### 6.4 Other types (slow path)

The slow path is rt 37 (`llvm.ridgun:107`). The x86 comments list: Int fast path, String `++`, List `::`, Int/Real arithmetic and comparison, structural `==` and `!=` (`x86_64.ridgun:838-848`). Deep equality and comparison live at `0x404000` (`x86_64.ridgun:980`).

- User overloads: functions named `+`, `-`, `*`, `/`, `%` with two parameters go into the binop dispatcher (fid 4) (`compiler.ridgun:4238-4255`). When rt 37 calls it is **UNKNOWN**.
- **UNKNOWN** for the slow path:
  - Real arithmetic, Real comparison, and mixed Int/Real operands;
  - String comparison with `<` and `>`;
  - op 0 on Strings (concat) versus op 14;
  - List concat and `::`;
  - flat join (15) and matmul (16);
  - errors for operand types that do not match;
  - whether the slow path consumes the left slot and the right value.
- The compiler emits `NStoreSlot sp` for the left value and then `NBinOp`; after it the slot is not cleared explicitly (`compiler.ridgun:2815-2819`). So rt 37 must consume or clear slot `sp`. Which one it does is **UNKNOWN**.

## 7. Program entry, page 0, concurrency

### 7.1 Image and page 0

- The ELF image is page 0, then the runtime, then the code, then the rodata (`elf64.ridgun:141-147`). One `PT_LOAD` at `0x400000`, flags RWX (7), memory size = file size + 131072 (`elf64.ridgun:123-126`).
- The entry point is `4198400` (`0x401000`) (`elf64.ridgun:130`).
- Page 0: ELF header (64 bytes), program header (56 bytes), 8 bytes of padding. At `0x400080` follow four function addresses: `main`, `spawn`, `call2`, `binop`. Then 3936 zero bytes (`elf64.ridgun:128-135`; `llvm.ridgun:634`).
- Windows: the PAL layer writes the address of `rg_pal` at `0x4000A0` at start. The runtime keeps variables at page-0 offsets `0x158..0x178` and `0xF00..0x1000`; they start at zero (`runtime_windows.md:17`, `:36`, `:46`). What those variables hold is **UNKNOWN**.
- The channel lock is a 32-bit word in 16 zero bytes between the code and the rodata, at `rodata_vaddr - 16` (`x86_64.ridgun:118-140`, `:1155-1169`; `gentensor.md:590`).
- The base rodata pool starts with fixed strings: `""`, `"+"`, `"-"`, `"*"`, `"/"`, `"%"`, `"Linux"` at +5, `"MacOS"` at +10, `"Windows"` at +15, `"X86_64"` at +22, `"Arm64"` at +28, `"Ok"`, `"Some"`, `"None"`, `"__rg_par_eval__"`, `"ki,k"`, `"i,j"`, `"i,i"`, `"ij,ij"`, `"__rg_rest__"` (`compiler.ridgun:969-975`).

### 7.2 Dispatcher functions

| fid | Name | Arity, slots | Role | Source |
|---|---|---|---|---|
| 1 | `__rg_entry_main` | 0, 2 (20 with agents) | calls the user entry; with agents also creates channels, starts agents, drains them | `compiler.ridgun:4367-4375` |
| 2 | `__rg_dispatch_spawn` | 2, 6 | slot 0 = name, slot 1 = argument; matches the name and calls the function; handles `__rg_par_eval__` and closures; no match returns 0 | `compiler.ridgun:4159-4195`, `:4581` |
| 3 | `__rg_dispatch_call2` | 3, max(7, 4 + highest arity) | (name, first argument, rest); a closure passes rest as a list inside `__rg_rest__` | `compiler.ridgun:4210-4236`, `:4582` |
| 4 | `__rg_dispatch_binop` | 3, 6 | user `+ - * / %` overloads | `compiler.ridgun:4238-4255`, `:4583` |
| >= 5 | user functions and field getters | — | — | `compiler.ridgun:4568-4569`, `:4584-4587` |

`NativeProg 1 2 3 4 fns rodata` names these four (`compiler.ridgun:4587`; `elf64.ridgun:13`).

### 7.3 Program start and exit

- x86-64: slot 0 code is the ELF entry: "argc/argv init & main invocation" (`x86_64.ridgun:950`).
- LLVM: `_start` is `0x401000`, the start of the linked x86 runtime image (`llvm.ridgun:647`).
- ARM64: `_start` loads `main` from `0x400080`, passes `SP` in `X0`, calls it, then calls `exit_group(0)` (`arm64.ridgun:521-522`).
- **UNKNOWN**: how argc/argv are stored for `cli_args`, the exit status on x86-64 after `main` returns, whether the result of `main` is printed or dropped, and what other runtime state `_start` sets up.

### 7.4 Agents, channels, jobs

- Agents use builtins 1, 32, 33, 50, 57, 59, 96, 98, 99 (`compiler.ridgun:2157-2329`). Language rules: `spec.md:960-990`; `FR-COMP-009`.
- Channel operations are not atomic in the runtime. Backends wrap 1, 32, 33 and 50 in a spin lock (cmpxchg, `sched_yield` = syscall 24 while waiting) (`llvm.ridgun:119`; `gentensor.md:590`).
- Blocking receive loops on try-receive (33) until it gets `Ok`, then takes field 0 (`llvm.ridgun:119`).
- Jobs:
  - Spawn (57): on a worker thread (thread id ≠ process id) it runs fid 2 inline and returns the tuple `(-999999, result)`. On the main thread it waits (`nanosleep` 100 µs) until one of 8 pool entries at `4288300 + 16*i` is free (i32 0 = free), then calls builtin 57 with `rsi` = the address of fid 2 (`llvm.ridgun:121`; `gentensor.md:591`; `x86_64.ridgun:457-499`).
  - Poll (58): a tuple means finished (True 6); else builtin 58 (`llvm.ridgun:121`).
  - Await (59): a tuple gives field 1; else builtin 59 (`llvm.ridgun:121`).
- **UNKNOWN**:
  - the channel object layout, its queue, and its capacity (also for bounded channels, id 35);
  - the timeout form 51;
  - the pool entry layout beyond "i32 0 = free", and how a worker thread is created (clone flags, stack size);
  - the job handle returned by 57 on the main thread;
  - what 58 and 59 do for a running job;
  - thread exit and the cleanup of agent threads.

## 8. Error behaviour summary

| Case | Behaviour | Source |
|---|---|---|
| Tensor or list index out of range | message `runtime error: tensor index out of range` on stderr, exit 1 (builtin 24) | `x86_64.ridgun:142-147`; `llvm.ridgun:733-748`; `gentensor.md:17` |
| `sort_by` lists of different lengths | `runtime error: sort by: the lists have different lengths` | `llvm.ridgun:764` |
| Extension errors (ids >= 100) | message on stderr, builtin 24 with Int 1 | `runtime_ext.md:245-251` |
| Int divide or remainder by 0 | result 0, no error | `llvm.ridgun:106` |
| No dispatcher match | result 0 | `compiler.ridgun:4167-4168`, `:4216-4217` |
| Pattern match failure (no case matches) | the compiler adds "no match" messages to the rodata (`compiler.ridgun:4565`); the runtime action is **UNKNOWN** | `compiler.ridgun:4565` |
| Other runtime entries on wrong input | **UNKNOWN** | — |

## 9. Conflicts found

| Topic | Source A | Source B | Reference for the new runtime |
|---|---|---|---|
| Names of slots 40..48 | x86 comments: 40 einsum, 41 hadamard, 42 seq_mask, 43 seq_indices, 44/45 region, 46..48 ctx (`x86_64.ridgun:871-916`) | LLVM symbols at the same addresses: 40 seq_select, 41 einsum, 42 hadamard, 47 enter_region, 48 exit_region (`llvm.ridgun:650-651`); encoder use (`x86_64.ridgun:442-452`); ARM64 names (`arm64.ridgun:396-509`) | B. The comment addresses equal the slot targets, but the comment names are shifted (for example, the comment "Slot 41 hadamard" sits at `0x408046`, which the linker script calls `__rg_rt_einsum`). |
| Bool and Unit words | `compiler_optimizations.md:215-218`: False 1, True 3, Unit 1 | code: False 2, True 6, Unit 0 (`compiler.ridgun:2786-2790`; `wasm.ridgun@HEAD:13-14`) | B (code) |
| Refcount location | RVal rc at -8 (`compiler_optimizations.md:219`) | RcVec header rc at +24 (`runtime_ext.md:706`; TASK-0068:29) | **UNKNOWN**; see 2.2 |
| `rebind_slot` order | "+1 new before -1 old" (`x86_64.ridgun:688`) | store new, then drop old as rt 10 (`wasm.ridgun@HEAD:335`; `llvm.ridgun:105`) | Both store the new word and drop the old word; the order matters only if both words are the same object. |
| Rotations in `bin_op` | inline (`llvm.ridgun:106`) | heap path (`wasm.ridgun@HEAD:378-383`) | LLVM |

## 10. UNKNOWN list (most important first)

1. Reference counting: where the count lives (RVal -8 or RcVec header +24), and what `clone_slot` / `drop_val` change for each tag. The full child cascade per tag.
2. The allocator: arena and slab design, reuse of freed memory, out-of-memory behaviour, the use of the 131072-byte zero area, and `pop_i64`.
3. The Tuple layout and tag, and the `Char` representation.
4. The `bin_op` slow path: Real arithmetic and comparison, mixed Int/Real, String comparison, concat (0 vs 14), list `::`, flat join (15), matmul (16), errors, and ownership of the left slot.
5. Semantics, ownership and errors of most rt 55 builtins (ids 0..62): `cli_args`, `shell_exec`, `int_to_str`, `str_slice`, `str_concat`, `str_starts_with`, `str_contains`, `write_file`, `char_from_code`, ids 35 and 51, and the unnamed ids behind split/replace/trim.
6. Ownership of slot arguments for rt 14..18, rt 27/28/30/32 (clone or borrow), and rt 53/54 frame setup.
7. Region enter/exit: quota handling, arena teardown, escaping values.
8. Program start: argc/argv storage, exit status on x86-64, use of page-0 variables.
9. Channels and jobs: channel layout, bounded channels, timeout receive, pool entry layout, thread creation, poll/await for running jobs.
10. cmm counter rules: what counts as a tracked block, when each counter changes.
11. The einsum spec grammar, the `seq_select` mask grammar, the hadamard broadcast rules, and the register arguments of rt 38/39.
12. The meaning of the inline `NMatchAdt` arities -1..-5, and the runtime action on a pattern match failure.
