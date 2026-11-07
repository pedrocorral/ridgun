# GenTensor internals (`FR-COMP-020`)

A *GenTensor* is a `Tensor` whose elements are not numbers (`String`, `Bool`, `Char`, lists, tuples, records, ADTs). This page explains how the compiler stores and accesses one. The language rules are in `docs/lang/spec.md` ("Tensors").

## Representation

- A one-dimensional GenTensor is a list value (heap tag `2`): an RC vector of boxed elements. `t_(i)` reads and writes the vector slot in place.
- A two-dimensional GenTensor is a list of row lists. Every row has its own RC vector, so a write never reaches another row or another tensor.
- Numeric tensors keep their representation (heap tag `5`, raw 64-bit words). The type checker keeps numeric-only operations away from GenTensors (`FR-COMP-020` §7).
- A GenTensor has one or two dimensions.

## Typing and lowering

- The type checker gives every tensor variable a kind and passes it to the lowering as an info entry `":tensor-elem:"` with the value `function|variable|kind`. Kinds: `N` (integers), `R` (`Real`), `L` (GenTensor of lists), `G` (other GenTensors) and `U` (unknown, for example a type variable or an ADT).
- Reads and writes of `G` variables use the GenTensor path: a bounds check, then `NIndex` or `NListSet`. `N` and `R` variables use the numeric path. `U` variables test the value at run time with `NIsList`.
- An index outside the shape writes `runtime error: tensor index out of range` to stderr and exits with status 1.
- Shape patterns (`(Tensor[T * r * c] g)`) on a GenTensor get the rank and dimensions from the helper `__rg_gt_shape t k flag` (k: 0 rank, 1 rows, 2 columns; flag 1 for `L` tensors, whose elements are lists themselves). For `U` pattern variables the code tests `NIsList` and runs the numeric or the GenTensor checks.

## Helper functions

`compiler.rg` adds Ridgun helper functions (`__rg_gt_*`) to a program that uses `Tensor[T * n]` with a non-numeric `T`, `Tensor[T * dims] with v`, `tensor from list` or `tensor to list`. Some of them are stubs: `lower expr` replaces calls to the stubs with native instructions.

| Native instruction | Stub | Result |
|---|---|---|
| `NIsList slot` | `__rg_gt_is_list v` | `True` when the value is a list |
| `NIsGen slot` | `__rg_gt_is_gen v` | `True` when the value is not a number |
| `NListSet base idx` | (writes) | stores the accumulator in a list slot and drops the old element |
| `NGtConv slot 0` | `__rg_gt_list_copy xs` | a new list with a clone of every element |
| `NGtConv slot 1` | `__rg_gt_list_tensor xs` | a one-dimensional numeric tensor from a list of numbers |
| `NGtConv slot 2` | `__rg_gt_tensor_ints t` | a list of `Int`s from the data of a numeric tensor |
| `NGtConv slot 3` | `__rg_gt_tensor_reals t` | a list of `Real`s from the data of a numeric tensor |
| `NGtConv slot 4` | (`:tensor-zeros:` with 3+ dimensions, `:tensor-with:`) | a numeric tensor of any rank from the list `[v, d1, ..., dn]`, every element equal to `v` |

The LLVM backend implements them in IR (`llvm gen tensor helpers`, `llvm gt conv helpers` in `llvm.rg`). The ARM64 encoder emits placeholders: its runtime has no `Real` or GenTensor support yet.

## x86-64 encodings of `NGtConv`

`x86_64.rg` stores the machine code of each mode as a byte list (`x86 gt conv bytes`). The encoder emits `mov rdi, [rsp + slot*8]` and then the bytes. The code saves `rbx` and `r12`-`r15`, keeps `rsp` 16-byte aligned and calls the runtime through `rax`. The addresses are those of the runtime blob, the same as in the LLVM linker script (`llvm.rg`).

To change a routine, edit its source below, assemble it and replace the byte list and its size (`x86 gt conv size`):

```bash
llvm-mc -triple=x86_64 -filetype=obj copy.s -o copy.o
llvm-objcopy -O binary --only-section=.text copy.o copy.bin
od -An -tu1 -v copy.bin
```

Every file starts with:

```asm
.intel_syntax noprefix
.set ALLOC_BUF, 4205566
.set BOX_RC_VEC, 4208821
.set BOX_RVAL, 4209847
.set CLONE_SLOT, 4198440
.set MAKE_LIST, 4198520
```

### Mode 0: copy a list (`copy.s`)

```asm
  push rbx
  push r12
  push r13
  push r14
  push r15
  sub rsp, 32
  xor r13d, r13d
  test rdi, rdi
  jz 1f
  test dil, 7
  jnz 1f
  mov rax, [rdi+8]
  mov r12, [rax+8]
  mov r13, [rax+16]
1:
  test r13, r13
  jnz 2f
  mov rdi, rsp
  xor esi, esi
  movabs rax, MAKE_LIST
  call rax
  jmp 9f
2:
  lea rdi, [r13*8]
  movabs rax, ALLOC_BUF
  call rax
  mov r14, rax
  xor ebx, ebx
3:
  mov rdi, [r12+rbx*8]
  movabs rax, CLONE_SLOT
  call rax
  mov [r14+rbx*8], rax
  inc rbx
  cmp rbx, r13
  jb 3b
  mov [rsp], r13
  mov [rsp+8], r14
  mov [rsp+16], r13
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov qword ptr [rsp], 2
  mov [rsp+8], rax
  mov qword ptr [rsp+16], 0
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
9:
  add rsp, 32
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
```

### Mode 1: list to numeric tensor (`totensor.s`)

```asm
  push rbx
  push r12
  push r13
  push r14
  push r15
  sub rsp, 32
  xor r13d, r13d
  test rdi, rdi
  jz 1f
  test dil, 7
  jnz 1f
  mov rax, [rdi+8]
  mov r12, [rax+8]
  mov r13, [rax+16]
1:
  mov edi, 8
  movabs rax, ALLOC_BUF
  call rax
  mov [rax], r13
  mov qword ptr [rsp], 1
  mov [rsp+8], rax
  mov qword ptr [rsp+16], 1
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov r15, rax
  lea rdi, [r13*8+8]
  movabs rax, ALLOC_BUF
  call rax
  mov r14, rax
  xor ebx, ebx
  test r13, r13
  jz 5f
3:
  mov rax, [r12+rbx*8]
  test al, 1
  jz 4f
  sar rax, 1
  jmp 6f
4:
  test rax, rax
  jz 6f
  test al, 7
  jnz 6f
  mov rax, [rax+8]
6:
  mov [r14+rbx*8], rax
  inc rbx
  cmp rbx, r13
  jb 3b
5:
  mov [rsp], r13
  mov [rsp+8], r14
  mov [rsp+16], r13
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov qword ptr [rsp], 5
  mov [rsp+8], r15
  mov [rsp+16], rax
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
  add rsp, 32
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
```

### Mode 2: numeric tensor to a list of Ints (`to_ints.s`)

```asm
  push rbx
  push r12
  push r13
  push r14
  push r15
  sub rsp, 32
  xor r13d, r13d
  test rdi, rdi
  jz 1f
  test dil, 7
  jnz 1f
  mov rax, [rdi+16]
  mov r12, [rax+8]
  mov r13, [rax+16]
1:
  test r13, r13
  jnz 2f
  mov rdi, rsp
  xor esi, esi
  movabs rax, MAKE_LIST
  call rax
  jmp 9f
2:
  lea rdi, [r13*8]
  movabs rax, ALLOC_BUF
  call rax
  mov r14, rax
  xor ebx, ebx
3:
  mov rax, [r12+rbx*8]
  lea rcx, [rax+rax]
  mov rdx, rcx
  sar rdx, 1
  cmp rdx, rax
  jne 4f
  or rcx, 1
  mov rax, rcx
  jmp 5f
4:
  movabs rcx, -9223372036854775808
  mov [rsp], rcx
  mov [rsp+8], rax
  mov qword ptr [rsp+16], 0
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
5:
  mov [r14+rbx*8], rax
  inc rbx
  cmp rbx, r13
  jb 3b
  mov [rsp], r13
  mov [rsp+8], r14
  mov [rsp+16], r13
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov qword ptr [rsp], 2
  mov [rsp+8], rax
  mov qword ptr [rsp+16], 0
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
9:
  add rsp, 32
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
```

### Mode 3: numeric tensor to a list of Reals (`to_reals.s`)

```asm
  push rbx
  push r12
  push r13
  push r14
  push r15
  sub rsp, 32
  xor r13d, r13d
  test rdi, rdi
  jz 1f
  test dil, 7
  jnz 1f
  mov rax, [rdi+16]
  mov r12, [rax+8]
  mov r13, [rax+16]
1:
  test r13, r13
  jnz 2f
  mov rdi, rsp
  xor esi, esi
  movabs rax, MAKE_LIST
  call rax
  jmp 9f
2:
  lea rdi, [r13*8]
  movabs rax, ALLOC_BUF
  call rax
  mov r14, rax
  xor ebx, ebx
3:
  mov rax, [r12+rbx*8]
  mov qword ptr [rsp], 0
  mov [rsp+8], rax
  mov qword ptr [rsp+16], 0
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
  mov [r14+rbx*8], rax
  inc rbx
  cmp rbx, r13
  jb 3b
  mov [rsp], r13
  mov [rsp+8], r14
  mov [rsp+16], r13
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov qword ptr [rsp], 2
  mov [rsp+8], rax
  mov qword ptr [rsp+16], 0
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
9:
  add rsp, 32
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
```

### Mode 4: numeric tensor of any rank (`shapefill.s`)

The input is the list `[v, d1, ..., dn]`. `v` becomes a raw word: a tagged `Int` is shifted right, a boxed number gives the word at `+8`. The routine builds the shape vector `[d1, ..., dn]` and a data vector of `d1 * ... * dn` copies of the word, then boxes `[5, shape, data]`. It reserves 48 bytes of stack, so `rsp` moves by 88 bytes in all (8 mod 16, as in modes 0-3).

```asm
  push rbx
  push r12
  push r13
  push r14
  push r15
  sub rsp, 48
  mov rax, [rdi+8]
  mov r12, [rax+8]
  mov r13, [rax+16]
  mov rax, [r12]
  test al, 1
  jz 1f
  sar rax, 1
  jmp 3f
1:
  test rax, rax
  jz 3f
  test al, 7
  jnz 3f
  mov rax, [rax+8]
3:
  mov [rsp+24], rax
  lea rdi, [r13*8]
  movabs rax, ALLOC_BUF
  call rax
  mov r14, rax
  mov qword ptr [rsp+32], 1
  mov ebx, 1
4:
  cmp rbx, r13
  jae 5f
  mov rax, [r12+rbx*8]
  sar rax, 1
  mov [r14+rbx*8-8], rax
  imul rax, [rsp+32]
  mov [rsp+32], rax
  inc rbx
  jmp 4b
5:
  lea rax, [r13-1]
  mov [rsp], rax
  mov [rsp+8], r14
  mov [rsp+16], rax
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov r15, rax
  mov rax, [rsp+32]
  lea rdi, [rax*8+8]
  movabs rax, ALLOC_BUF
  call rax
  mov r14, rax
  xor ebx, ebx
  mov rcx, [rsp+24]
  mov rdx, [rsp+32]
6:
  cmp rbx, rdx
  jae 7f
  mov [r14+rbx*8], rcx
  inc rbx
  jmp 6b
7:
  mov [rsp], rdx
  mov [rsp+8], r14
  mov [rsp+16], rdx
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov qword ptr [rsp], 5
  mov [rsp+8], r15
  mov [rsp+16], rax
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
  add rsp, 48
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
```

## Other x86-64 encodings for numeric tensors

The pure x86-64 encoder needs three more routines so that numeric tensor elements behave as on LLVM (0.9.39):

- **Borrowed reads** (`NIndex b i -1` and `-2`, `x86 borrowed index`). The lowering reads a tensor variable without giving up its reference. The runtime index call (rt 38) consumes its base slot, so the encoder clones the base into a 16-byte stack area and indexes that copy, as LLVM's `@__rg_tensor_index_1d` does.
- **One- and two-dimensional allocation** (`NCallBuiltin 88`, `x86 tensor fill slots`). The runtime builtin dispatcher has no tensor fill. The encoder runs the body of mode 4 with `r12` pointing to the slots `[fill, d0, d1]` and `r13` = their count.
- **`Real` writes** (`NIndexSet`, `x86 real to int bits`). The runtime index set (rt 39) stores an `Int`, so a `Real` lost its bits. Before the call, a `Real` (64-bit header `0`) becomes the `Int` with the same bits and the `Real` is dropped. LLVM does the same in `@__rg_real_to_int_bits` before `@__rg_rt_index_set`, which it calls for tensors with three or more dimensions.

The `Real` conversion (`realbits.s`) runs on the value in `rax`. `DROP_VAL` is rt 6 (`4198400 + 6*8`):

```asm
.set DROP_VAL, 4198448
.set DROP_VAL, 4198448
  test rax, rax
  jz 9f
  test al, 7
  jnz 9f
  cmp qword ptr [rax], 0
  jne 9f
  push rbx
  push r12
  sub rsp, 40
  mov rbx, rax
  mov r12, [rax+8]
  mov rdi, rbx
  movabs rax, DROP_VAL
  call rax
  lea rax, [r12+r12]
  mov rcx, rax
  sar rcx, 1
  cmp rcx, r12
  jne 1f
  or rax, 1
  jmp 2f
1:
  movabs rax, -9223372036854775808
  mov [rsp], rax
  mov [rsp+8], r12
  mov qword ptr [rsp+16], 0
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
2:
  add rsp, 40
  pop r12
  pop rbx
9:
```

### One- and two-dimensional writes in place (`idxset1.s`, `idxset2.s`)

Since 0.9.40 `NIndexSet` with one or two indices first runs a fast path (`x86 index set fast`), as LLVM's `@__rg_tensor_index_set_1d` / `_2d` do. When the base is a numeric tensor of that rank, the indices are `Int`s in range and the value is an `Int` or has a 64-bit payload (header `0`: a `Real` or a large `U64`), the raw word goes straight into the tensor data. A tensor shared with a caller (a function argument, a row given to `||map f in m_(i,)`) therefore sees the write. In every other case the code falls through to the runtime call above (149 bytes, `x86 index set call`). The encoder emits `lea rdi, [base slot]`, `lea rsi, [index slots]` and then the bytes; the value is in `rax`. `idxset2.s` differs from `idxset1.s` only between the rank test and the store:

```asm
  mov rdx, rax
  test dl, 1
  jz 1f
  sar rdx, 1
  xor r8d, r8d
  jmp 2f
1:
  test rax, rax
  jz 9f
  test al, 7
  jnz 9f
  cmp dword ptr [rax], 0
  jne 9f
  mov rdx, [rax+8]
  mov r8, rax
2:
  mov r9, [rdi]
  test r9, r9
  jz 9f
  test r9b, 7
  jnz 9f
  cmp dword ptr [r9], 5
  jne 9f
  mov r10, [r9+8]
  cmp qword ptr [r10+16], 1
  jne 9f
  mov rcx, [rsi]
  test cl, 1
  jz 9f
  sar rcx, 1
  js 9f
  mov r11, [r9+16]
  cmp rcx, [r11+16]
  jge 9f
  mov r11, [r11+8]
  mov [r11+rcx*8], rdx
  mov qword ptr [rdi], 0
  mov qword ptr [rsi], 0
  mov rax, r9
  test r8, r8
  jz 8f
  push rbx
  mov rbx, r9
  mov rdi, r8
  movabs rax, DROP_VAL
  call rax
  mov rax, rbx
  pop rbx
8:
  .byte 0xe9
  .long 149
9:
```

The two-dimensional part of `idxset2.s`:

```asm
  cmp qword ptr [r10+16], 2
  jne 9f
  mov rcx, [rsi]
  mov r11, [rsi+8]
  test cl, 1
  jz 9f
  test r11b, 1
  jz 9f
  sar rcx, 1
  js 9f
  sar r11, 1
  js 9f
  mov r10, [r10+8]
  cmp rcx, [r10]
  jge 9f
  cmp r11, [r10+8]
  jge 9f
  imul rcx, [r10+8]
  add rcx, r11
  mov r11, [r9+16]
  cmp rcx, [r11+16]
  jge 9f
  mov r11, [r11+8]
  mov [r11+rcx*8], rdx
  mov qword ptr [rdi], 0
  mov qword ptr [rsi], 0
  mov qword ptr [rsi+8], 0
```

## x86-64 encodings of builtins 89-99, channels and jobs

The LLVM backend implements builtins 89-99 as IR helpers in `llvm.rg`, and wraps the runtime channel and job builtins (1, 32, 33, 50, 57, 58, 59). The runtime builtin dispatcher has none of this, so since 0.9.40 the pure x86-64 encoder emits one routine per builtin (`x86 builtin bytes` / `x86 builtin size` in `x86_64.rg`). Each routine does what its LLVM helper does:

| Builtin | LLVM helper | Source | Before the bytes the encoder emits |
|---|---|---|---|
| 89 `sha256 raw (a + b)` | `@__rg_builtin_sha256_concat` | (no routine) | see below |
| 90 element-wise `+ - *`, `and or xor`, tensor clone | `@__rg_builtin_tensor_bitop` | `bitop.s` | `lea rdi, [slots]` |
| 91 `str char at s i` (local `s`) | `@__rg_str_char_at_fast` | `charat.s` | `mov rdi, [slot of s]`; the index is in `rax` |
| 92 `m_(r,)` | `@__rg_builtin_tensor_row_slice` | `rowslice.s` | `lea rdi, [slots]` |
| 93 write of `m_(r,)` | `@__rg_builtin_tensor_set_row` | `setrow.s` | `lea rdi, [slots]` |
| 94 `m_(,c)` | `@__rg_builtin_tensor_col_slice` | `colslice.s` | `lea rdi, [slots]` |
| 95 write of `m_(,c)` | `@__rg_builtin_tensor_set_col` | `setcol.s` | `lea rdi, [slots]` |
| 96 thread id | `@__rg_builtin_gettid` | `gettid.s` | nothing |
| 97 send `(tid, v)` | `@__rg_builtin_chan_send_tagged` | `sendtag.s` | `lea rdi, [slots]`, `mov rsi, LOCK` |
| 98 receive this thread's reply | `@__rg_builtin_chan_try_recv_tagged` | `tryrecvtag.s` | `lea rdi, [slots]`, `mov rsi, count`, `mov rdx, LOCK` |
| 99 take this thread's job from a list | `@__rg_builtin_list_extract_tid` | `extracttid.s` | `lea rdi, [slots]` |
| 1, 32 (count 0), 33, 50 | `@__rg_builtin_chan_new` / `_recv_nonblock` / `_try_recv` / `_send` | `chanop.s` | `mov rdi, id`, `lea rsi, [slots]`, `mov rdx, count`, `mov rcx, LOCK` |
| 32 (blocking receive) | `@__rg_builtin_chan_recv` | `chanrecv.s` | `lea rdi, [slots]`, `mov rsi, LOCK` |
| 57 spawn a job | `@__rg_builtin_job_spawn` | `jobspawn.s` | `lea rdi, [slots]`, `mov rsi, address of function 2` |
| 58 poll a job | `@__rg_builtin_job_poll` | `jobpoll.s` | `lea rdi, [slots]` |
| 59 await a job | `@__rg_builtin_job_await` | `jobawait.s` | `lea rdi, [slots]` |

- **Builtin 89** has no routine: the encoder (`x86 sha256 concat`) concatenates the two strings with the runtime binary operator (rt 37, operator 0) as `NBinOp` does, clears slot `b`, stores the result in slot `a` and runs the `sha256 raw` sequence (builtin 36). The digest is the same as LLVM's; LLVM avoids building the concatenated string.
- **The channel lock.** Agents run on several threads and the runtime channel builtins are not atomic. LLVM serialises them with a spin lock (`@__rg_chan_lock`). On x86 the lock is a 32-bit word in 16 zero bytes that `emit x8664 elf kind` reserves between the code and the rodata (`LOCK` = rodata address − 16, `x86 chan lock`); the single `PT_LOAD` segment is writable. The routines take it with `lock cmpxchg` and `sched_yield` (syscall 24) between tries, and release it with a plain store.
- **Jobs.** A spawn from a worker thread (thread id ≠ process id) runs function 2 inline and returns the tuple `(-999999, result)`; poll and await treat a tuple as a finished job. A spawn from the main thread waits (`nanosleep` 100 µs) until one of the 8 entries of the runtime job pool at `4288300` is free. Without this, nested agents starve the pool.

All routines save the callee-saved registers they use, call the runtime through `rax` with `rsp` 16-byte aligned (the instruction-level `rsp` is 8 mod 16) and leave the result in `rax`. Routines with local subroutines or data (`fdrop`, the string `"Ok"` for `MATCH_ADT`) end with a jump over them. Build each file as in "x86-64 encodings of `NGtConv`", with this header and the `ACQUIRE` macro:

```asm
.intel_syntax noprefix
.set DROP_SLOT, 4200437
.set ALLOC_BUF, 4205566
.set BOX_RC_VEC, 4208821
.set BOX_RVAL, 4209847
.set CLONE_SLOT, 4214484
.set DROP_VAL, 4214519
.set MAKE_LIST, 4214925
.set MAKE_TUPLE, 4214963
.set MATCH_NONEMPTY, 4216495
.set LIST_HEAD, 4216538
.set LIST_TAIL, 4216614
.set MATCH_TUPLE, 4216754
.set TUPLE_GET, 4216825
.set MATCH_ADT, 4216940
.set ADT_FIELD, 4217065
.set RT_BUILTIN, 4241227
.macro ACQUIRE reg
.Lacq\@:
  xor eax, eax
  mov ecx, 1
  lock cmpxchg dword ptr [\reg], ecx
  je .Lgot\@
  mov eax, 24
  syscall
  jmp .Lacq\@
.Lgot\@:
.endm
```

### `bitop.s`

NCallBuiltin 90: rdi = slots [A, B, op]. Element-wise op of two numeric tensors.

```asm
  push rbx
  push r12
  push r13
  push r14
  push r15
  sub rsp, 32
  mov rbx, rdi
  mov r15, [rbx+16]
  mov qword ptr [rbx+16], 0
  sar r15, 1
  mov rax, [rbx]
  mov rax, [rax+8]
  mov r12, [rax+16]
  lea rdi, [r12*8]
  movabs rax, ALLOC_BUF
  call rax
  mov r13, rax
  mov rdi, rax
  mov rax, [rbx]
  mov rax, [rax+8]
  mov rsi, [rax+8]
  lea rcx, [r12*8]
  rep movsb
  mov [rsp], r12
  mov [rsp+8], r13
  mov [rsp+16], r12
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov r13, rax
  mov rax, [rbx]
  mov rax, [rax+16]
  mov r14, [rax+16]
  lea rdi, [r14*8]
  movabs rax, ALLOC_BUF
  call rax
  mov r12, rax
  mov rax, [rbx]
  mov rax, [rax+16]
  mov rsi, [rax+8]
  mov rax, [rbx+8]
  mov rax, [rax+16]
  mov rdx, [rax+8]
  xor ecx, ecx
1:
  cmp rcx, r14
  jge 9f
  mov rax, [rsi+rcx*8]
  mov rdi, [rdx+rcx*8]
  cmp r15, 0
  je 2f
  cmp r15, 1
  je 3f
  cmp r15, 2
  je 4f
  cmp r15, 11
  je 5f
  cmp r15, 12
  je 6f
  xor rax, rdi
  jmp 8f
2:
  add rax, rdi
  jmp 8f
3:
  sub rax, rdi
  jmp 8f
4:
  imul rax, rdi
  jmp 8f
5:
  and rax, rdi
  jmp 8f
6:
  or rax, rdi
8:
  mov [r12+rcx*8], rax
  inc rcx
  jmp 1b
9:
  mov [rsp], r14
  mov [rsp+8], r12
  mov [rsp+16], r14
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov qword ptr [rsp], 5
  mov [rsp+8], r13
  mov [rsp+16], rax
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
  mov r12, rax
  mov rdi, rbx
  movabs rax, DROP_SLOT
  call rax
  lea rdi, [rbx+8]
  movabs rax, DROP_SLOT
  call rax
  mov rax, r12
  add rsp, 32
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
```

### `charat.s`

NCallBuiltin 91: rdi = the string (borrowed), rax = the index. Byte at the index as an Int.

```asm
  mov rsi, rax
  test sil, 1
  jz 7f
  test rdi, rdi
  jz 7f
  test dil, 7
  jnz 7f
  cmp dword ptr [rdi], 1
  jne 7f
  mov rcx, rsi
  sar rcx, 1
  mov rdx, [rdi+8]
  cmp rcx, [rdx+16]
  jae 6f
  mov rdx, [rdx+8]
  movzx eax, byte ptr [rdx+rcx]
  lea rax, [rax+rax+1]
  jmp 9f
6:
  mov rax, -1
  jmp 9f
7:
  push rbx
  sub rsp, 16
  mov rbx, rsi
  movabs rax, CLONE_SLOT
  call rax
  mov [rsp], rax
  mov [rsp+8], rbx
  mov edi, 40
  mov rsi, rsp
  mov edx, 2
  movabs rax, RT_BUILTIN
  call rax
  add rsp, 16
  pop rbx
9:
```

### `rowslice.s`

NCallBuiltin 92: rdi = slots [m, r]. Row r of a matrix as a vector (zeros when out of range).

```asm
  push rbx
  push r12
  push r13
  push r14
  push r15
  sub rsp, 32
  mov rbx, rdi
  mov r12, [rbx+8]
  mov qword ptr [rbx+8], 0
  sar r12, 1
  mov rax, [rbx]
  mov rax, [rax+8]
  mov rax, [rax+8]
  mov r13, [rax]
  mov r14, [rax+8]
  mov edi, 8
  movabs rax, ALLOC_BUF
  call rax
  mov [rax], r14
  mov qword ptr [rsp], 1
  mov [rsp+8], rax
  mov qword ptr [rsp+16], 1
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov r15, rax
  lea rdi, [r14*8]
  movabs rax, ALLOC_BUF
  call rax
  mov rdi, rax
  lea rcx, [r14*8]
  test r12, r12
  js 2f
  cmp r12, r13
  jge 2f
  mov r13, rdi
  mov rax, [rbx]
  mov rax, [rax+16]
  mov rsi, [rax+8]
  mov rax, r12
  imul rax, r14
  lea rsi, [rsi+rax*8]
  rep movsb
  jmp 3f
2:
  mov r13, rdi
  xor eax, eax
  rep stosb
3:
  mov [rsp], r14
  mov [rsp+8], r13
  mov [rsp+16], r14
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov qword ptr [rsp], 5
  mov [rsp+8], r15
  mov [rsp+16], rax
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
  mov r12, rax
  mov rdi, rbx
  movabs rax, DROP_SLOT
  call rax
  mov rax, r12
  add rsp, 32
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
```

### `setrow.s`

NCallBuiltin 93: rdi = slots [m, r, v]. Copies v into row r of m in place; returns m.

```asm
  push rbx
  push r12
  sub rsp, 8
  mov rbx, rdi
  mov r12, [rbx]
  mov rax, [rbx+8]
  mov qword ptr [rbx], 0
  mov qword ptr [rbx+8], 0
  sar rax, 1
  mov rcx, [r12+8]
  mov rcx, [rcx+8]
  mov rdx, [rcx]
  mov r8, [rcx+8]
  test rax, rax
  js 9f
  cmp rax, rdx
  jge 9f
  mov rsi, [rbx+16]
  mov rsi, [rsi+16]
  mov rcx, [rsi+16]
  mov rsi, [rsi+8]
  cmp rcx, r8
  cmovge rcx, r8
  shl rcx, 3
  imul rax, r8
  mov rdi, [r12+16]
  mov rdi, [rdi+8]
  lea rdi, [rdi+rax*8]
  rep movsb
9:
  lea rdi, [rbx+16]
  movabs rax, DROP_SLOT
  call rax
  mov rax, r12
  add rsp, 8
  pop r12
  pop rbx
```

### `colslice.s`

NCallBuiltin 94: rdi = slots [m, c]. Column c of a matrix as a vector.

```asm
  push rbx
  push r12
  push r13
  push r14
  push r15
  sub rsp, 32
  mov rbx, rdi
  mov r12, [rbx+8]
  mov qword ptr [rbx+8], 0
  sar r12, 1
  mov rax, [rbx]
  mov rax, [rax+8]
  mov rax, [rax+8]
  mov r13, [rax]
  mov r14, [rax+8]
  mov edi, 8
  movabs rax, ALLOC_BUF
  call rax
  mov [rax], r13
  mov qword ptr [rsp], 1
  mov [rsp+8], rax
  mov qword ptr [rsp+16], 1
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov r15, rax
  lea rdi, [r13*8]
  movabs rax, ALLOC_BUF
  call rax
  mov rcx, [rbx]
  mov rcx, [rcx+16]
  mov rsi, [rcx+8]
  lea rsi, [rsi+r12*8]
  xor ecx, ecx
1:
  cmp rcx, r13
  jge 2f
  mov rdx, [rsi]
  mov [rax+rcx*8], rdx
  lea rsi, [rsi+r14*8]
  inc rcx
  jmp 1b
2:
  mov [rsp], r13
  mov [rsp+8], rax
  mov [rsp+16], r13
  mov rdi, rsp
  movabs rax, BOX_RC_VEC
  call rax
  mov qword ptr [rsp], 5
  mov [rsp+8], r15
  mov [rsp+16], rax
  mov rdi, rsp
  movabs rax, BOX_RVAL
  call rax
  mov r12, rax
  mov rdi, rbx
  movabs rax, DROP_SLOT
  call rax
  mov rax, r12
  add rsp, 32
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbx
```

### `setcol.s`

NCallBuiltin 95: rdi = slots [m, c, v]. Copies v into column c of m in place; returns m.

```asm
  push rbx
  push r12
  sub rsp, 8
  mov rbx, rdi
  mov r12, [rbx]
  mov rax, [rbx+8]
  mov qword ptr [rbx], 0
  mov qword ptr [rbx+8], 0
  sar rax, 1
  mov rcx, [r12+8]
  mov rcx, [rcx+8]
  mov rdx, [rcx]
  mov r8, [rcx+8]
  mov rsi, [rbx+16]
  mov rsi, [rsi+16]
  mov rcx, [rsi+16]
  mov rsi, [rsi+8]
  cmp rcx, rdx
  cmovge rcx, rdx
  mov rdi, [r12+16]
  mov rdi, [rdi+8]
  lea rdi, [rdi+rax*8]
  xor eax, eax
1:
  cmp rax, rcx
  jge 9f
  mov rdx, [rsi+rax*8]
  mov [rdi], rdx
  lea rdi, [rdi+r8*8]
  inc rax
  jmp 1b
9:
  lea rdi, [rbx+16]
  movabs rax, DROP_SLOT
  call rax
  mov rax, r12
  add rsp, 8
  pop r12
  pop rbx
```

### `gettid.s`

NCallBuiltin 96: the thread id (gettid) as an Int.

```asm
  mov eax, 186
  syscall
  lea rax, [rax+rax+1]
```

### `sendtag.s`

NCallBuiltin 97: rdi = slots [v, chan], rsi = the channel lock. Sends (tid, v) through chan under the lock.

```asm
  push rbx
  push r12
  push r13
  sub rsp, 16
  mov rbx, rdi
  mov r13, rsi
  mov r12, [rbx]
  mov eax, 186
  syscall
  lea rax, [rax+rax+1]
  mov [rsp], rax
  mov [rsp+8], r12
  mov rdi, rsp
  mov esi, 2
  movabs rax, MAKE_TUPLE
  call rax
  mov [rbx], rax
  ACQUIRE r13
  mov edi, 50
  mov rsi, rbx
  mov edx, 2
  movabs rax, RT_BUILTIN
  call rax
  mov dword ptr [r13], 0
  add rsp, 16
  pop r13
  pop r12
  pop rbx
```

### `tryrecvtag.s`

NCallBuiltin 98: rdi = slots [chan], rsi = allow_fallback, rdx = the channel lock. Under the lock, takes the first (tid, v) of this thread from chan and returns (3, v); with allow_fallback and no match, takes the first item. Returns 0 when there is none.

```asm
  push rbx
  push rbp
  push r12
  push r13
  push r14
  push r15
  sub rsp, 8216
  mov rbx, [rdi]
  mov qword ptr [rdi], 0
  mov r13, rsi
  mov [rsp+8208], rdx
  mov eax, 186
  syscall
  lea r12, [rax+rax+1]
  mov rdx, [rsp+8208]
  ACQUIRE rdx
  mov [rsp], rbx
  mov edi, 33
  mov rsi, rsp
  mov edx, 1
  movabs rax, RT_BUILTIN
  call rax
  mov rbp, rax
  mov rdi, rax
  lea rsi, [rip+ok_str]
  mov edx, 2
  mov ecx, 1
  movabs rax, MATCH_ADT
  call rax
  test rax, rax
  jnz 1f
  mov rax, [rsp+8208]
  mov dword ptr [rax], 0
  mov rdi, rbp
  call fdrop
  xor eax, eax
  jmp ret_out
1:
  mov rdi, rbp
  xor esi, esi
  movabs rax, ADT_FIELD
  call rax
  mov r14, rax
  mov rdi, rbp
  call fdrop
  mov rdi, r14
  mov esi, 2
  movabs rax, MATCH_TUPLE
  call rax
  test rax, rax
  jz 2f
  mov rdi, r14
  xor esi, esi
  movabs rax, TUPLE_GET
  call rax
  cmp rax, r12
  jne 2f
  mov rax, [rsp+8208]
  mov dword ptr [rax], 0
  mov rdi, r14
  mov esi, 1
  movabs rax, TUPLE_GET
  call rax
  mov rbp, rax
  mov rdi, r14
  call fdrop
  mov qword ptr [rsp], 3
  mov [rsp+8], rbp
  mov rdi, rsp
  mov esi, 2
  movabs rax, MAKE_TUPLE
  call rax
  jmp ret_out
2:
  mov [rsp+16], r14
  mov r14d, 1
  mov r15, -1
3:
  cmp r14, 1024
  jge 5f
  mov [rsp], rbx
  mov edi, 33
  mov rsi, rsp
  mov edx, 1
  movabs rax, RT_BUILTIN
  call rax
  mov rbp, rax
  mov rdi, rax
  lea rsi, [rip+ok_str]
  mov edx, 2
  mov ecx, 1
  movabs rax, MATCH_ADT
  call rax
  test rax, rax
  jnz 4f
  mov rdi, rbp
  call fdrop
  jmp 5f
4:
  mov rdi, rbp
  xor esi, esi
  movabs rax, ADT_FIELD
  call rax
  mov [rsp+16+r14*8], rax
  mov rdi, rbp
  call fdrop
  test r15, r15
  jns 41f
  mov rdi, [rsp+16+r14*8]
  mov esi, 2
  movabs rax, MATCH_TUPLE
  call rax
  test rax, rax
  jz 41f
  mov rdi, [rsp+16+r14*8]
  xor esi, esi
  movabs rax, TUPLE_GET
  call rax
  cmp rax, r12
  jne 41f
  mov r15, r14
41:
  inc r14
  jmp 3b
5:
  test r15, r15
  jns 51f
  test r13, r13
  jz 51f
  xor r15d, r15d
51:
  xor r12d, r12d
  xor r13d, r13d
6:
  cmp r12, r14
  jge 7f
  mov rax, [rsp+16+r12*8]
  cmp r12, r15
  jne 61f
  mov r13, rax
  jmp 62f
61:
  mov [rsp], rax
  mov [rsp+8], rbx
  mov edi, 50
  mov rsi, rsp
  mov edx, 2
  movabs rax, RT_BUILTIN
  call rax
62:
  inc r12
  jmp 6b
7:
  mov rax, [rsp+8208]
  mov dword ptr [rax], 0
  test r15, r15
  js 8f
  mov rdi, r13
  mov esi, 2
  movabs rax, MATCH_TUPLE
  call rax
  test rax, rax
  jz 71f
  mov rdi, r13
  mov esi, 1
  movabs rax, TUPLE_GET
  call rax
  mov rbp, rax
  mov rdi, r13
  call fdrop
  mov r13, rbp
71:
  mov qword ptr [rsp], 3
  mov [rsp+8], r13
  mov rdi, rsp
  mov esi, 2
  movabs rax, MAKE_TUPLE
  call rax
  jmp ret_out
8:
  xor eax, eax
ret_out:
  add rsp, 8216
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbp
  pop rbx
  jmp end_out
fdrop:
  test rdi, rdi
  jz 1f
  test dil, 7
  jnz 1f
  movabs rax, DROP_VAL
  jmp rax
1:
  ret
ok_str:
  .ascii "Ok"
end_out:
```

### `extracttid.s`

NCallBuiltin 99: rdi = slots [list]. Takes the first (tid, j) of this thread from the list (else the first item) and returns (j, rest).

```asm
  push rbx
  push rbp
  push r12
  push r13
  push r14
  push r15
  sub rsp, 16408
  mov rbx, rdi
  mov eax, 186
  syscall
  lea r12, [rax+rax+1]
  mov rdi, [rbx]
  movabs rax, LIST_HEAD
  call rax
  mov rbp, rax
  mov rdi, rax
  mov esi, 2
  movabs rax, MATCH_TUPLE
  call rax
  test rax, rax
  jz 2f
  mov rdi, rbp
  xor esi, esi
  movabs rax, TUPLE_GET
  call rax
  cmp rax, r12
  jne 3f
  mov rdi, rbp
  mov esi, 1
  movabs rax, TUPLE_GET
  call rax
  mov r13, rax
  mov rdi, rbp
  call fdrop
  mov rdi, [rbx]
  movabs rax, LIST_TAIL
  call rax
  mov r14, rax
  mov rdi, rbx
  movabs rax, DROP_SLOT
  call rax
  mov [rsp], r13
  mov [rsp+8], r14
  jmp 1f
2:
  mov rdi, [rbx]
  movabs rax, LIST_TAIL
  call rax
  mov r14, rax
  mov rdi, rbx
  movabs rax, DROP_SLOT
  call rax
  mov [rsp], rbp
  mov [rsp+8], r14
1:
  mov rdi, rsp
  mov esi, 2
  movabs rax, MAKE_TUPLE
  call rax
  jmp ret_out
3:
  mov [rsp+16], rbp
  mov rdi, [rbx]
  movabs rax, LIST_TAIL
  call rax
  mov r13, rax
  mov rdi, rbx
  movabs rax, DROP_SLOT
  call rax
  mov r14d, 1
  mov r15, -1
4:
  cmp r14, 1024
  jge 5f
  mov rdi, r13
  movabs rax, MATCH_NONEMPTY
  call rax
  test rax, rax
  jz 5f
  mov rdi, r13
  movabs rax, LIST_HEAD
  call rax
  mov rbp, rax
  mov rdi, r13
  movabs rax, LIST_TAIL
  call rax
  mov rdi, r13
  mov r13, rax
  call fdrop
  mov [rsp+16+r14*8], rbp
  test r15, r15
  jns 41f
  mov rdi, rbp
  mov esi, 2
  movabs rax, MATCH_TUPLE
  call rax
  test rax, rax
  jz 41f
  mov rdi, rbp
  xor esi, esi
  movabs rax, TUPLE_GET
  call rax
  cmp rax, r12
  jne 41f
  mov r15, r14
41:
  inc r14
  jmp 4b
5:
  mov rdi, r13
  call fdrop
  test r15, r15
  jns 51f
  xor r15d, r15d
51:
  xor r12d, r12d
  xor r13d, r13d
  xor ebp, ebp
6:
  cmp r12, r14
  jge 7f
  mov rax, [rsp+16+r12*8]
  cmp r12, r15
  jne 61f
  mov rbp, rax
  jmp 62f
61:
  mov [rsp+8208+r13*8], rax
  inc r13
62:
  inc r12
  jmp 6b
7:
  lea rdi, [rsp+8208]
  mov rsi, r13
  movabs rax, MAKE_LIST
  call rax
  mov r13, rax
  mov rdi, rbp
  mov esi, 1
  movabs rax, TUPLE_GET
  call rax
  mov r12, rax
  mov rdi, rbp
  call fdrop
  mov [rsp], r12
  mov [rsp+8], r13
  mov rdi, rsp
  mov esi, 2
  movabs rax, MAKE_TUPLE
  call rax
ret_out:
  add rsp, 16408
  pop r15
  pop r14
  pop r13
  pop r12
  pop rbp
  pop rbx
  jmp end_out
fdrop:
  test rdi, rdi
  jz 1f
  test dil, 7
  jnz 1f
  movabs rax, DROP_VAL
  jmp rax
1:
  ret
end_out:
```

### `chanop.s`

Builtins 1, 32 (count 0), 33 and 50: rdi = builtin id, rsi = slots, rdx = count, rcx = the channel lock. The runtime builtin under the lock.

```asm
  push rbx
  push r12
  push r13
  push r15
  sub rsp, 8
  mov rbx, rdi
  mov r12, rsi
  mov r13, rdx
  mov r15, rcx
  ACQUIRE r15
  mov rdi, rbx
  mov rsi, r12
  mov rdx, r13
  movabs rax, RT_BUILTIN
  call rax
  mov dword ptr [r15], 0
  add rsp, 8
  pop r15
  pop r13
  pop r12
  pop rbx
```

### `chanrecv.s`

Builtin 32 (blocking receive): rdi = slots [chan], rsi = the channel lock. Polls with try-receive (33) under the lock and sched_yield between tries.

```asm
  push rbx
  push r12
  push r13
  sub rsp, 16
  mov rbx, [rdi]
  mov qword ptr [rdi], 0
  mov r12, rsi
1:
  mov [rsp], rbx
  ACQUIRE r12
  mov edi, 33
  mov rsi, rsp
  mov edx, 1
  movabs rax, RT_BUILTIN
  call rax
  mov dword ptr [r12], 0
  mov r13, rax
  mov rdi, rax
  lea rsi, [rip+ok_str]
  mov edx, 2
  mov ecx, 1
  movabs rax, MATCH_ADT
  call rax
  test rax, rax
  jnz 2f
  mov rdi, r13
  call fdrop
  mov eax, 24
  syscall
  jmp 1b
2:
  mov rdi, r13
  xor esi, esi
  movabs rax, ADT_FIELD
  call rax
  mov rbx, rax
  mov rdi, r13
  call fdrop
  mov rax, rbx
  add rsp, 16
  pop r13
  pop r12
  pop rbx
  jmp end_out
fdrop:
  test rdi, rdi
  jz 1f
  test dil, 7
  jnz 1f
  movabs rax, DROP_VAL
  jmp rax
1:
  ret
ok_str:
  .ascii "Ok"
end_out:
```

### `jobspawn.s`

Builtin 57: rdi = slots, rsi = the address of function 2. On a worker thread (tid != pid) runs function 2 inline and returns (-999999, result); otherwise waits for a free slot in the runtime job pool (8 entries of 16 bytes at 4288300) and spawns the job with runtime builtin 57.

```asm
  push rbx
  push r12
  push r13
  sub rsp, 16
  mov rbx, rdi
  mov r12, rsi
  mov eax, 186
  syscall
  mov r13, rax
  mov eax, 39
  syscall
  cmp r13, rax
  jne 5f
1:
  xor ecx, ecx
2:
  cmp rcx, 8
  jge 3f
  mov rdx, rcx
  shl rdx, 4
  mov eax, dword ptr [rdx+4288300]
  test eax, eax
  jz 4f
  inc rcx
  jmp 2b
3:
  mov qword ptr [rsp], 0
  mov qword ptr [rsp+8], 100000
  mov eax, 35
  mov rdi, rsp
  xor esi, esi
  syscall
  jmp 1b
4:
  mov edi, 57
  mov rsi, rbx
  mov edx, 2
  movabs rax, RT_BUILTIN
  call rax
  jmp 9f
5:
  sub rsp, 8
  mov rdi, rbx
  call r12
  add rsp, 8
  mov qword ptr [rsp], -1999997
  mov [rsp+8], rax
  mov rdi, rsp
  mov esi, 2
  movabs rax, MAKE_TUPLE
  call rax
9:
  add rsp, 16
  pop r13
  pop r12
  pop rbx
```

### `jobpoll.s`

Builtin 58: rdi = slots [job]. An inline job (a tuple) is ready (6); otherwise runtime builtin 58.

```asm
  push rbx
  mov rbx, rdi
  mov rdi, [rbx]
  mov esi, 2
  movabs rax, MATCH_TUPLE
  call rax
  test rax, rax
  jz 1f
  mov rdi, rbx
  movabs rax, DROP_SLOT
  call rax
  mov eax, 6
  jmp 9f
1:
  mov edi, 58
  mov rsi, rbx
  mov edx, 1
  movabs rax, RT_BUILTIN
  call rax
9:
  pop rbx
```

### `jobawait.s`

Builtin 59: rdi = slots [job]. An inline job (a tuple) gives its second element; otherwise runtime builtin 59.

```asm
  push rbx
  push r12
  sub rsp, 8
  mov rbx, rdi
  mov rdi, [rbx]
  mov esi, 2
  movabs rax, MATCH_TUPLE
  call rax
  test rax, rax
  jz 1f
  mov rdi, [rbx]
  mov esi, 1
  movabs rax, TUPLE_GET
  call rax
  mov r12, rax
  mov rdi, rbx
  movabs rax, DROP_SLOT
  call rax
  mov rax, r12
  jmp 9f
1:
  mov edi, 59
  mov rsi, rbx
  mov edx, 1
  movabs rax, RT_BUILTIN
  call rax
9:
  add rsp, 8
  pop r12
  pop rbx
```

## Bounds checks on numeric tensors (0.9.41)

FR-COMP-020 §8 applies to numeric tensors too. The fast paths already check the index; every out-of-range index reaches a slow path, and the checks sit there:

- **LLVM.** `@__rg_tensor_bounds(base, idx, count)` runs in the four `@__rg_tensor_index*_slow` helpers and before the general `@__rg_rt_index` / `@__rg_rt_index_set` calls. On a numeric tensor (heap tag `5`) with at least `count` dimensions, an Int index outside `0 <= i < d` calls `@__rg_tensor_oob`, which writes the message to stderr and exits through builtin 24 (`sys exit 1`).
- **x86-64.** `x86 tensor bounds` (`bounds.s`, 178 bytes) runs before rt 38 in every `NIndex`, and at the start of every `NIndexSet` (`x86 index set bounds`), before the fast path. It reads rdi (base slot), rsi (index slots) and rdx (count) and uses r8-r11 only.
- **Slices.** `m_(r,)`, `m_(,c)` and their writes check the row or column in the lowering (`lower dim bounds`, with `NAdtField b (-10 - k)` = dimension k).

Builtin 24 is called through the runtime builtin entry rt 55 (`4198400 + 55*8`):

```asm
.set RT_BUILTIN, 4198840
.set RT_BUILTIN, 4198840
  mov r8, [rdi]
  test r8, r8
  jz 9f
  test r8b, 7
  jnz 9f
  cmp dword ptr [r8], 5
  jne 9f
  mov r8, [r8+8]
  cmp rdx, [r8+16]
  jg 9f
  mov r8, [r8+8]
  xor r11d, r11d
1:
  cmp r11, rdx
  jge 9f
  mov r9, [rsi+r11*8]
  test r9b, 1
  jz 2f
  sar r9, 1
  js 3f
  cmp r9, [r8+r11*8]
  jge 3f
2:
  inc r11
  jmp 1b
3:
  mov eax, 1
  mov edi, 2
  lea rsi, [rip+4f]
  mov edx, 41
  syscall
  push 3
  mov rsi, rsp
  mov edi, 24
  mov edx, 1
  movabs rax, RT_BUILTIN
  call rax
  ud2
4:
  .ascii "runtime error: tensor index out of range\n"
9:
```

## Copies on send (0.9.41)

FR-COMP-020 §13. The type checker reports, for each send (`send_to`, `ask_to`, `send_through`, `chan_send`, an agent's initial state), the tensor variables and the calls returning a tensor in the message (`:tensor-elem:` facts, `fn|()f|K` for a call to `f`). Lowering wraps each in `:msg-copy:` (`msg copy expr`, also inside a tuple). At run time a list (a GenTensor) is copied by `__rg_gt_copy_any` (rows too) and a numeric tensor by the same copy as `t_` (builtin 90, op 12); any other value passes.
