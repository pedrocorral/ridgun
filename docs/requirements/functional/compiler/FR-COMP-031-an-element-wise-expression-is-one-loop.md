---
id: FR-COMP-031
title: An element-wise expression on tensors is one loop over machine words
status: implemented
priority: must
created: 2026-11-19
updated: 2026-11-19
depends_on:
  - FR-COMP-020
  - FR-COMP-022
  - FR-COMP-030
related:
  - ADR-0013
verified_by: []
---
# FR-COMP-031 — An element-wise expression on tensors is one loop over machine words

## Statement
1. **The expression.** An element-wise expression is built from tensor reads with subscripts (`a_ij`, `a_i`), numbers (an `Int` or a `Real`, the same for every element) and the operators `+ - * / %`, `and or xor`, `shl shr rotl rotr`, with any depth and parentheses: `((a_i + b_i) xor d_i) rotl 16`. Its value is a new tensor with the operators applied to each element.
2. **Subscripts.** One letter is enough for a tensor of one dimension (`a_i`; the letters are `i j k l`). Every tensor read has the subscripts of the result, its first ones or its last ones: `a_ij + b_j` uses `b` along the first dimension, `a_ij * c_i` uses `c` along the last. Other combinations keep the older form of two tensors (`a_ij + b_ji`).
3. **Element types.** All the tensors of one expression have the same element type. The type gives the width and the arithmetic:
   - `Int`, `U64`, `I64`, `Usize`: 64 bits; `+ - *` wrap at 2^64, `/` and `%` are signed.
   - `U8`, `U16`, `U32`: 8, 16 and 32 bits, unsigned; `+ - *` wrap at that width and `rotl`, `rotr` rotate in it.
   - `Real`: IEEE 754 binary64 (FR-COMP-030); `+ - * /` only, and its numbers are `Real`.
   - In every integer type a shift or rotation count is taken modulo the width, `shr` is logical, and `/` and `%` by zero give 0.
4. **Packed tensors.** `Tensor[U16]` and `Tensor[U32]` store 2 and 4 bytes per element, as `Tensor[U8]` stores 1 (FR-COMP-022). Each is its own type: compatible only with a tensor of the same element type. An element reads as an `Int`; writing an `Int` outside the range of the type stops the program (`runtime error: U32 element out of 0..4294967295`). The interfaces of bytes (strings, files, hashes, system calls) take `Tensor[U8]` only.
5. **One loop.** An expression runs as one pass over the elements: each operand is read once and the result written once, with no call and no allocation per operator.
6. **Several statements, one loop.** Consecutive statements of a block that each bind an element-wise expression, over tensors of one element type and with the same subscripts, run as one loop with several results; a value one statement gives to a later one is not stored in between. The element type must be known from the text: a parameter typed `Tensor[U32 * n]`, a tensor made with `Tensor[U32 * n]`, or a result of such a statement.
7. **In place.** A tensor that the expression reads for the last time, and that nothing else holds, takes a result instead of a new tensor. A tensor with another name or another owner is never written.
8. **The instructions of the machine.** With the LLVM back end the loop is in the program itself, on untagged elements of the machine type, in three versions: plain x86-64, AVX2 and AVX-512. The program runs the widest the machine has; `RIDGUN_CPU=2` or `RIDGUN_CPU=3` in the environment keeps it at the plain or the AVX2 version. The other back ends (the pure x86-64 encoder, WebAssembly) run the same expression in the runtime, element by element: the same result, slower.
9. **Errors.** At compile time: tensors of different element types, a tensor of a type that is not a number, a `Real` tensor with an `Int` number or with an operator other than `+ - * /`, subscripts that do not fit. At run time: tensors whose numbers of elements differ stop the program with `runtime error: element-wise expression: the shapes differ`.

## Rationale
The cryptography of the libraries used tensors as arrays and did every step element by element on `Int`, because an operator on tensors was a call to the runtime that read two tensors and allocated a third, and because every element had 64 bits. Hand-written kernel code for the same algorithms is fast for reasons a compiler can give to any tensor expression: elements of the width of their type, values kept in registers across operations, one instruction for many elements, and no call or allocation in the loop. None of this is special to cryptography: the same rule serves linear algebra, filters on columns, images, hashes and counting.

## Acceptance Criteria
1. **AC-1**: `(a_ij * k) + 1`, `(a_ij shr 4) and 0xFF` and `((a_ij + b_ij) xor d_ij) rotl 16` give the values of `tests/cases/tensors/fused_elementwise_expressions.ridgun`.
2. **AC-2**: `(a_k xor b_k) + 1` on `Tensor[U64 * n]` builds and gives one value per element.
3. **AC-3**: `a_ij + b_j` and `a_ij * b_i` use `b` along the first and along the last dimension.
4. **AC-4**: the same expressions work on `Tensor[U8]` (wrapping at 256) and on `Tensor[Real]` with `Real` numbers.
5. **AC-5**: on `Tensor[U32]`, `0xFFFFFFFF + 2` is `1` and `(0xFFFFFFFF xor 2) rotl 16` is `4294836223`; on `Tensor[U16]`, `((40000 * 3) + 65535) rotr 4` is `64843`.
6. **AC-6**: an element of a `Tensor[U32 * 2 * 3]` reads back the `Int` written; writing `4294967296` stops the program.
7. **AC-7**: the eight statements of the ChaCha20 quarter round on four `Tensor[U32 * n]` give the result of RFC 8439 section 2.1.1 in every element.
8. **AC-8**: after `kept = x` and `s = add x y`, `x` and `kept` keep their values; `add s y`, where `s` is not used again, gives the sum.
9. **AC-9**: `a_i * 2` on a `Tensor[Real]` and `a_i xor b_i` on a `Tensor[U32]` and a `Tensor[U8]` do not build.
10. **AC-10**: tensors of 3 and 4 elements in `a_i + b_i` stop the program with the message of point 9.
11. **AC-11**: every case above prints the same with the LLVM back end at levels 2, 3 and 4 (`tests/runtime/run-fuse-levels.sh`), with the pure x86-64 encoder and with WebAssembly.

## Not in scope
- Signed packed types (`I8`, `I16`, `I32`): they keep 64 bits per element.
- Comparisons and reductions (sum, minimum) inside an element-wise expression.
- Selection by a tensor of indices, products wider than the element, and carry-less multiplication.
- Statements joined across function calls: a loop is made of statements written one after the other in one block.
- ARM64, Windows and macOS: their runtime is not the IR runtime yet (TASK-0096).
