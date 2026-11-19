# Fused element-wise expressions: how they are compiled

Requirement: `FR-COMP-031`. Design task: `TASK-0103`.

## The path of an expression
| Step | Where | What it does |
|---|---|---|
| 1. Recognise | `parser.ridgun`, `make add or hadamard` and `fuse late expr` | An operator with a tensor read on one side becomes `ECall ":fuse:" ((EStr code):leaves)`. Reads with two or more subscript letters are seen while parsing; one-letter reads (`a_i`) after names are resolved, when `a_i` is known not to be a variable. |
| 2. Join statements | `parser.ridgun`, `fuse blocks stmts` | A run of consecutive statements that bind fused expressions of one known element type and the same subscripts becomes one node with several results, bound to a tuple and unpacked. |
| 3. Type | `typecheck.ridgun`, `fuse check` | Element types agree, numbers have the type of the elements, subscripts fit. The result is a tensor, or a tuple of tensors. |
| 4. Give operands away | `compiler.ridgun`, `move fuse once` and `fuse with moves` | A tensor read for the last time is moved into its slot, not shared. |
| 5. Lower | `compiler.ridgun`, `lower expr` of `":fuse:"` | The leaves go to consecutive slots; `NHadamard 99 slot off len` names the program text in the read-only data. The text starts with the element kind, known from the facts of the type checker. |
| 6a. Run, LLVM | `llvm.ridgun`, `llvm fuse fn` | One function per program, three times (plain, AVX2, AVX-512) and a dispatcher. |
| 6b. Run, others | `src/main/runtime/core/fuse.ll`, `rg_fuse` | `__rg_rt_hadamard` with operator 99 runs the program element by element. |

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

The program starts with the kind and a bar: `W|e e x0 w0 ...`. Kinds: `N` 64-bit integers, `R` Reals, `B` U8, `H` U16, `W` U32.

Rule every program keeps: element i of every leaf is read before element i of any result is written. The statements of a run put their `o` tokens at the end. This is what lets a result be one of the tensors the program reads (`rg_fuse_take`).

## Packed tensors
`Tensor[U16]` and `Tensor[U32]` use the layout of `Tensor[U8]` (`runtime_ext.md`): the first data word is `rank + (lg << 32)`, `lg` the element size as a power of two, so a `Tensor[U8]` is unchanged. Builtin 141 `(lg, fill, d1 .. dk)` makes one; reads and writes are builtins 105 and 106, which take the size from the tensor. The lowering treats the kinds `H` and `W` as `B` everywhere but in a fused program (`packed as b`).

## The LLVM function
- Elements are loaded and stored with the machine type of the kind (`i8`, `i16`, `i32`, `i64`, `double`); rotations are `llvm.fshl` and `llvm.fshr`.
- Loads and stores carry `!llvm.access.group` and the loop `llvm.loop.parallel_accesses`: elements at different indices never depend on each other, so the vectoriser needs no overlap checks, however many tensors a program reads and writes.
- The three versions differ only in `"target-features"`. `rg_cpu_level` (fuse.ll) reads the flags the system lists in `/proc/cpuinfo` once; `RIDGUN_CPU` lowers the level.
- `RIDGUN_KEEP_IR=<file>` keeps the IR of a build, to read what a program got.

## Measured on 2026-11-19 (AMD Ryzen 7 8845HS, one core)
| Case | Time |
|---|---|
| One fused call, one result, one element (the fixed cost) | 24 ns |
| ChaCha20 quarter round, 64 blocks at once, eight statements written apart (eight calls) | 360 ns |
| The same eight statements in one block (one loop, results in place) | 97 ns |
| The same with the runtime routine (pure x86-64 encoder) | about 5 000 ns |

## Not done
- A small tensor of fixed shape as a register value across calls (design point D3 of `TASK-0103`).
- The fixed cost of a run with several results is the tuple and its unpacking.
- Tests of the AVX-512 version need a machine that has it; `tests/runtime/run-fuse-levels.sh` runs the levels the machine has.
