# Fused element-wise expressions: how they are compiled

Requirement: `FR-COMP-031`. Design task: `TASK-0103`.

## The path of an expression
| Step | Where | What it does |
|---|---|---|
| 1. Recognise | `parser.ridgun`, `make add or hadamard` and `fuse late expr` | An operator with a tensor read on one side becomes `ECall ":fuse:" ((EStr code):leaves)`. Reads with two or more subscript letters are seen while parsing; one-letter reads (`a_i`) after names are resolved, when `a_i` is known not to be a variable. |
| 2. Join statements | `parser.ridgun`, `fuse blocks stmts` | A run of consecutive statements that bind fused expressions of one known element type and the same subscripts becomes one node with several results, bound to a tuple and unpacked. |
| 3. Type | `typecheck.ridgun`, `fuse check` | Element types agree, numbers have the type of the elements, subscripts fit. The result is a tensor, or a tuple of tensors. |
| 4. Give operands away | `compiler.ridgun`, `move fuse once` and `fuse with moves` | A tensor read for the last time is moved into its slot, not shared. |
| 5. Lower | `compiler.ridgun`, `lower expr` of `":fuse:"` | The leaves go to consecutive slots; `NHadamard (1000 + kinds) slot off len` names the program text in the read-only data and carries the element kind of each tensor, known from the facts of the type checker. |
| 6a. Run, LLVM | `llvm.ridgun`, `llvm fuse fn` | One function per program and kinds, three times (plain, AVX2, AVX-512) and a dispatcher. |
| 6b. Run, others | `src/main/runtime/core/fuse.ll`, `rg_fuse` | `__rg_rt_hadamard` with an operator of 1000 or more runs the program element by element. |

## The two texts
The node of the syntax tree keeps the subscripts; the program the runtime reads keeps how each tensor lies in the result.

| In the tree (`ast.ridgun`) | In the program (`fuse.ll`) | Meaning |
|---|---|---|
| `t<subs>` | `e`, `p` or `u` | the next leaf, a tensor: of the shape of the result, of its first dimensions, of its last ones |
| `s` | `s` | the next leaf, a number |
| `c<n>` | `c<n>` | the integer n |
| `x<id>` | `x<id>` | a binary operator (`binop id`) |
| `w<k>`, `l<k>` | the same | set value k from the top of the stack; read value k |
| `o` | `o` | the top of the stack is the next result |
| `b` ... `g` | ... `g` | `t_(index)`: the index tokens, then `g` reads the next leaf (a tensor) at the index on top |
| `r<id>` | `r<id>` | the last token: one number from all the elements (0 sum, 30 smallest, 31 largest) |

The kinds are not in the text: `kinds` is a number with one digit of 3 bits per tensor leaf, the first leaf lowest (1 `N` 64-bit integers, 2 `R` Reals, 3 `B` U8, 4 `H` U16, 5 `W` U32); leaves after the 20th have the kind of the 20th. A value has the kind of the tensor it was read from, a number takes the kind of the value it meets, and an operator gives the kind of its operands. Both runners follow the kinds through the program once, before the loop.

Rule every program keeps: element i of every `e` leaf is read before element i of any result is written. The statements of a run put their `o` tokens at the end. This is what lets a result be one of the tensors the program reads (`rg_fuse_take`); only an `e` leaf of the kind of the result can be taken, never a tensor read by index.

## Operators that are not one instruction everywhere
- `mulhi` (21): in the LLVM function, a product at twice the width; in the runtime, from 32-bit halves (`rg_mulhi`, binop.ll), because wasm32 has no 128-bit product without a library.
- `clmul`, `clmulhi` (22, 23): `rg_clmul_soft` (binop.ll) is the definition, one bit at a time. `__rg_clmul` (abi/helpers.ll) uses PCLMULQDQ at CPU level 3 and up; the LLVM function and the scalar fast path call it.
- A program that reads by index or gives one number, and also reads along rows (`p` or `u`), is not specialised: its function calls the runtime.

## Packed tensors
`Tensor[U16]` and `Tensor[U32]` use the layout of `Tensor[U8]` (`runtime_ext.md`): the first data word is `rank + (lg << 32)`, `lg` the element size as a power of two, so a `Tensor[U8]` is unchanged. Builtin 141 `(lg, fill, d1 .. dk)` makes one; reads and writes are builtins 105 and 106, which take the size from the tensor. The lowering treats the kinds `H` and `W` as `B` everywhere but in a fused program (`packed as b`).

## The LLVM function
- Elements are loaded and stored with the machine type of the kind (`i8`, `i16`, `i32`, `i64`, `double`); rotations are `llvm.fshl` and `llvm.fshr`.
- Loads and stores carry `!llvm.access.group` and the loop `llvm.loop.parallel_accesses`: elements at different indices never depend on each other, so the vectoriser needs no overlap checks, however many tensors a program reads and writes.
- The three versions differ only in `"target-features"`. `rg_cpu_level` (fuse.ll) reads the flags the system lists in `/proc/cpuinfo` once; `RIDGUN_CPU` lowers the level.
- An index is checked without leaving the loop: an index outside reads element 0 and sets a flag; after the loop the flag stops the program.
- A reduction is a value carried by the loop; integers are joined at 64 bits. A sum of `Real`s keeps the order of the elements, so it is not vectorised.
- `RIDGUN_KEEP_IR=<file>` keeps the IR of a build, to read what a program got.

## Measured on 2026-11-19 (AMD Ryzen 7 8845HS, one core)
| Case | Time |
|---|---|
| One fused call, one result, one element (the fixed cost) | 24 ns |
| ChaCha20 quarter round, 64 blocks at once, eight statements written apart (eight calls) | 360 ns |
| The same eight statements in one block (one loop, results in place) | 97 ns |
| The same with the runtime routine (pure x86-64 encoder) | about 5 000 ns |
| ChaCha20, 20 rounds, 64 blocks at once (the key stream of 4096 bytes), 16 tensors of `U32`, each double round one block of 64 statements; checked against RFC 8439 2.3.2 | 8.8 µs |
| of which: making the 16 tensors and the counters | 2.1 µs |
| of which: the ten double rounds (ten loops of 16 tensors in, 16 out) | 5.4 µs |
| The same at CPU level 2 (plain x86-64) | 11 µs |
| The same with the runtime routine (pure x86-64 encoder) | 575 µs |

What the last figures say: the vector width changes little, so the time is no longer in the loops. It is in the fixed cost of a fused call with many results: opening 16 leaves, 16 results, a tuple of 16 and its unpacking, and the call of a function of 17 arguments.

## Not done
- A small tensor of fixed shape as a register value across calls (design point D3 of `TASK-0103`).
- The fixed cost of a run with several results (about 500 ns for 16 tensors in and 16 out) is now most of the time of a small loop: the leaves are opened one call each, the results come back in a tuple that is unpacked, and a function of more than 8 arguments takes the slow call path.
- Tests of the AVX-512 version need a machine that has it; `tests/runtime/run-fuse-levels.sh` runs the levels the machine has.
