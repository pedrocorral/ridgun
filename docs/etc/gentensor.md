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

`compiler.rg` adds Ridgun helper functions (`__rg_gt_*`) to a program that uses `Tensor[T * n]` with a non-numeric `T`, `tensor fill`, `tensor from list` or `tensor to list`. Some of them are stubs: `lower expr` replaces calls to the stubs with native instructions.

| Native instruction | Stub | Result |
|---|---|---|
| `NIsList slot` | `__rg_gt_is_list v` | `True` when the value is a list |
| `NIsGen slot` | `__rg_gt_is_gen v` | `True` when the value is not a number |
| `NListSet base idx` | (writes) | stores the accumulator in a list slot and drops the old element |
| `NGtConv slot 0` | `__rg_gt_list_copy xs` | a new list with a clone of every element |
| `NGtConv slot 1` | `__rg_gt_list_tensor xs` | a one-dimensional numeric tensor from a list of numbers |
| `NGtConv slot 2` | `__rg_gt_tensor_ints t` | a list of `Int`s from the data of a numeric tensor |
| `NGtConv slot 3` | `__rg_gt_tensor_reals t` | a list of `Real`s from the data of a numeric tensor |

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

