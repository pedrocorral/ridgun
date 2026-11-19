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
1. **The expression.** An element-wise expression is built from tensor reads with subscripts (`a_ij`, `a_i`), numbers (an `Int` or a `Real`, the same for every element) and the operators `+ - * / %`, `and or xor`, `shl shr rotl rotr`, `mulhi clmul clmulhi`, with any depth and parentheses: `((a_i + b_i) xor d_i) rotl 16`. Its value is a new tensor with the operators applied to each element.
2. **Subscripts.** One letter is enough for a tensor of one dimension (`a_i`; the letters are `i j k l`). Every tensor read has the subscripts of the result, its first ones or its last ones: `a_ij + b_j` uses `b` along the first dimension, `a_ij * c_i` uses `c` along the last. Other combinations keep the older form of two tensors (`a_ij + b_ji`).
3. **Element types.** All the tensors of one expression have the same element type. The type gives the width and the arithmetic:
   - `Int`, `U64`, `I64`, `Usize`: 64 bits; `+ - *` wrap at 2^64, `/` and `%` are signed.
   - `U8`, `U16`, `U32`: 8, 16 and 32 bits, unsigned; `+ - *` wrap at that width and `rotl`, `rotr` rotate in it.
   - `Real`: IEEE 754 binary64 (FR-COMP-030); `+ - * /` only, and its numbers are `Real`.
   - In every integer type a shift or rotation count is taken modulo the width, `shr` is logical, and `/` and `%` by zero give 0.
4. **Packed tensors.** `Tensor[U16]` and `Tensor[U32]` store 2 and 4 bytes per element, as `Tensor[U8]` stores 1 (FR-COMP-022). Each is its own type: compatible only with a tensor of the same element type. An element reads as an `Int`; writing an `Int` outside the range of the type stops the program (`runtime error: U32 element out of 0..4294967295`). The interfaces of bytes (strings, files, hashes, system calls) take `Tensor[U8]` only.
5. **One loop.** An expression runs as one pass over the elements: each operand is read once and the result written once, with no call and no allocation per operator.
6. **Several statements, one loop.** Consecutive statements of a block that each bind an element-wise expression, over tensors of one element type and with the same subscripts, run as one loop with several results; a value one statement gives to a later one is not stored in between. The element type must be known from the text: a parameter typed `Tensor[U32 * n]`, a tensor made with `Tensor[U32 * n]`, or a result of such a statement.
   A function that does one such loop on its tensors and then calls itself with the results and one less in its counter runs as that loop done that many times, without a call in between:
   ```ridgun
   fn :: rounds Tensor[U32 * n] Tensor[U32 * n] Int => Tensor[U32 * n] Tensor[U32 * n]
         rounds a b k
           | k <= 0 = (a, b)
           | otherwise =
             a1 = a_i + b_i
             b1 = (b_i xor a1_i) rotl 7
             rounds a1 b1 (k - 1)
   ```
   The form that is recognised: the counter is the last parameter; the first branch is `k <= 0` and gives back some of the parameters, in their order (the state); the second is the statements of one loop followed by the call, with one new name for each tensor of the state and `k - 1`. Every other parameter goes to the call as it is (a tensor that does not change, a table read by index), or, when it is a number, with a constant added or taken away (`at + 4`): the loop then reads a number that moves by that much each time. The loop does not read the state by index.
   Statements that read a tensor by index join a loop like the others, when that tensor does not come from the statements of the loop.
7. **In place.** A tensor that the expression reads for the last time, and that nothing else holds, takes a result instead of a new tensor. A tensor with another name or another owner is never written.
8. **The instructions of the machine.** With the LLVM back end the loop is in the program itself, on untagged elements of the machine type, in three versions: plain x86-64, AVX2 and AVX-512. The program runs the widest the machine has; `RIDGUN_CPU=2` or `RIDGUN_CPU=3` in the environment keeps it at the plain or the AVX2 version. The other back ends (the pure x86-64 encoder, WebAssembly) run the same expression in the runtime, element by element: the same result, slower.
9. **Wide and carry-less products.** Three operators on integers, on plain `Int`s and element-wise:
   - `a mulhi b`: the high half of the product of the two numbers taken as unsigned, at the width of the type (64 bits for `Int`). With `*`, which gives the low half, it is the whole product.
   - `a clmul b` and `a clmulhi b`: the low and the high half of the product without carries (the product of two polynomials over GF(2)), at the width of the type.
   - With the LLVM back end `clmul` on 64 bits uses the instruction of the processor when it has one (PCLMULQDQ); elsewhere it is computed bit by bit.
10. **Selection by index.** Inside an element-wise expression `t_(index)`, with an element-wise expression as the index, reads `t` at the index each element gives: `t_(x_i)`, `t_((x_i shr 4) and 15)`. `t` has any shape and is read as one row of elements. The tensors of the index are integers and may have another element type than `t`; the result has the element type of `t` and the shape of the index. An index outside `t` stops the program (`runtime error: tensor index out of range`).
11. **One number from all the elements.** `tensor sum e`, `tensor min e` and `tensor max e`, where `e` is an element-wise expression or a tensor, run in the loop of the expression and give one number: an `Int` for integer tensors (elements are joined as 64-bit numbers: a sum of bytes is not cut to a byte; `min` and `max` compare `Int` elements as signed), a `Real` for `Real` tensors. With no elements the result is 0.
12. **Bytes and words.** The elements of a packed tensor are stored with their low byte first, so the same bytes can be read as elements of another width:
   - `tensor bytes t`: a `Tensor[U8]` of one dimension with the bytes of a `Tensor[U8]`, `Tensor[U16]` or `Tensor[U32]`.
   - `tensor u16 from bytes b` and `tensor u32 from bytes b`: a tensor of one dimension with the bytes of a `Tensor[U8]` as elements of that width. Bytes that are not a whole number of elements stop the program.
   - `tensor interleave [t0, t1, ...]`: the tensors of the list (of one element type and one number of elements n) side by side: a tensor of one dimension whose element `i * k + j` is element `i` of tensor `j`. It turns "one tensor per word, n blocks each" into "n blocks, one after the other".
   - `tensor get le32 b off step n` (and `be32`, `le16`, `be16`, `le64`, `be64`): a tensor of one dimension with the `n` words read from the bytes of `b` at `off`, `off + step`, ..., in that byte order. `tensor put le32 b off step w` (and the others) writes the words of `w` there. Words of 16 and 32 bits are `Tensor[U16]` and `Tensor[U32]`; of 64 bits, a tensor of 64-bit elements. A word outside the bytes stops the program (`runtime error: byte range out of bounds`).
13. **Width.** `e as U8`, `e as U16`, `e as U32` and `e as U64` give an integer at another width: cut to it, or widened with zeros. Inside an element-wise expression it lets tensors of two element types meet (`msg_i xor (w_i as U8)`); on a plain `Int` it keeps the low bits.
14. **Writing by index.** `t_(index) = value`, with an element-wise index, writes each value at its index of `t`: `q_(p_i) = v_i + 1`. The elements go in their order: when two name one place the last wins, and an element that reads `t` reads what the ones before it wrote. An index outside `t` stops the program.
15. **Errors.** At compile time: tensors of different element types, a tensor of a type that is not a number, a `Real` tensor with an `Int` number or with an operator other than `+ - * /`, subscripts that do not fit. At run time: tensors whose numbers of elements differ stop the program with `runtime error: element-wise expression: the shapes differ`.

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
10. **AC-10**: tensors of 3 and 4 elements in `a_i + b_i` stop the program with the message of point 15.
11. **AC-11**: every case here prints the same with the LLVM back end at levels 2, 3 and 4 (`tests/runtime/run-fuse-levels.sh`), with the pure x86-64 encoder and with WebAssembly.
12. **AC-12**: `t_(x_i)` on a table of 4 bytes and indices `3 0 2 1 3` gives the bytes in that order; `(t_(p_i + 1) xor k_i) rotl 8` with `t` a `Tensor[U32]` and `p` a `Tensor[U8]` builds; an index 4 into 4 elements stops the program; an index made of a `Real` tensor does not build.
13. **AC-13**: `tensor sum (a_i * b_i)` on `Real` tensors is the dot product; `tensor sum` of 1000 bytes of 255 is 255000; `tensor max (a_i xor b_i)` is 0 for equal tensors; `tensor sum`, `tensor min` and `tensor max` of a tensor of no elements are 0.
14. **AC-14**: `(0 - 1) mulhi (0 - 1)` is `-2` (2^64 - 2), `0x100000000 mulhi 0x100000000` is 1; on `Tensor[U32]`, `0xFFFFFFFF mulhi 0x10000` is `65535`.
15. **AC-15**: `3 clmul 3` is 5, `7 clmul 5` is 27, `0x8000000000000000 clmulhi 2` is 1; element-wise on `U64` and `U8` the results are those of the bit-by-bit definition, with and without the instruction of the processor.
17. **AC-17**: the quarter round of ChaCha20 written as such a function gives, for 0, 1, 2 and 20 times on 300 elements, the result of doing the step that many times one call at a time, and for 1 time the result of RFC 8439 2.1.1; the tensors given to it keep their values.
18. **AC-18**: `tensor u32 from bytes` of the bytes of `"abcdefgh"` is `1684234849 1751606885`, `tensor bytes` of it gives the 8 bytes back; `tensor interleave [x, y, z]` of three tensors of 3 elements has 9 elements, `x_0 y_0 z_0 x_1 ...`; 5 bytes as `U32` stop the program; `tensor bytes` of a `Tensor[U64]` does not build.
19. **AC-19**: ChaCha20 on a page of 4096 bytes (64 blocks at once: the rounds, `tensor interleave` of the 16 tensors, `tensor bytes`, and `xor` with the message) gives the bytes of an implementation written apart, which gives the bytes of RFC 8439 2.4.2; encrypting the result gives the message back.
20. **AC-20**: a step with a state of two tensors, a tensor that does not change, a table read by index and a number that moves by 3, written as a function that calls itself, gives for 0, 1, 2 and 9 times the result of one call for each time.
21. **AC-21**: from the bytes of `"abcdefghijklmnop"`, `tensor get le32 b 0 4 4` is `1684234849 1751606885 1818978921 1886350957` and `tensor get be32` is `1633837924 ...`; `tensor put le32 out 0 8 w` and `tensor put be32 out 4 8 w` on 16 bytes give `abcddcbaefghhgfe`; a word at byte 13 of 16 stops the program; `tensor put le32` with a `Tensor[U16]` does not build.
22. **AC-22**: `msg_i xor (w_i as U8)` on a `Tensor[U8]` and a `Tensor[U32]` builds and uses the low byte; `(b_i as U32) shl 24` widens; `0x1FF as U8` is 255.
23. **AC-23**: `q_(p_i) = v_i + 1` with `p = 7 0 3 3` and `v = 10 20 30 40` leaves `41` at place 3; `q_(p_i) = q_i` with `p = 1 2 3 3` on `1 2 3 4` leaves `1 1 1 1`; an index of 4 into 4 elements stops the program.
24. **AC-24**: twelve statements in a row that each read a `Tensor[U8]` and a `Tensor[U64]` by index give the values of the statements done one by one (a loop with tensors of several element types takes at most 20 tensors; the statements after them make another loop). One expression with more than 20 tensors of several types does not build.
16. **AC-16**: every integer operator on `U8`, `U16`, `U32` and `U64` tensors gives the value of its definition (`src/test/ridgun/test operator matrix.ridgun`, rows `E`).

## Not in scope
- Signed packed types (`I8`, `I16`, `I32`): they keep 64 bits per element.
- Comparisons inside an element-wise expression; reductions other than sum, smallest and largest.
- An element-wise expression with tensors of several element types reads at most 20 tensors (one with a single type, any number).
- Statements that give one number, or write by index, are not joined with their neighbours into one loop.
- A loop that runs several times and also gives one number, writes by index or reads along rows runs in the runtime, element by element.
- `tensor bytes` of a tensor of 64-bit elements (`tensor put le64` does it).
- Statements joined across function calls: a loop is made of statements written one after the other in one block.
- ARM64, Windows and macOS: their runtime is not the IR runtime yet (TASK-0096).
