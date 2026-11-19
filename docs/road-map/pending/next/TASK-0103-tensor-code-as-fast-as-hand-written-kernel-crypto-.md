---
id: TASK-0103
title: Tensor code as fast as hand-written kernel crypto, without assembly: design
status: pending             # pending | going-on | blocked | completed
created: 2026-11-18
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0103 — Tensor code as fast as hand-written kernel crypto, without assembly: design

## Goal (one sentence)
State what a `Tensor` must compile to so that ChaCha20-Poly1305 written in Ridgun runs at the speed of the kernel's implementation, with no assembly in the compiler, the runtime or the library.

## The reasoning
The kernel's code is fast for five reasons, none of them a trick:
1. A word is a machine word of the width of its type: `u32` arithmetic wraps by itself, no mask.
2. The state stays in registers during a whole block; nothing is loaded or stored between two operations.
3. One vector register holds the same state word of 8 or 16 blocks, so one instruction works on 8 or 16 blocks.
4. No call, no bounds check and no allocation inside the loop.
5. Rotation, 64 x 64 -> 128 multiplication and carry-less multiplication are one instruction each.

A tensor today fails 1 to 4: every element is a 64-bit word whatever its type; each element-wise operator is a call to a loop of the runtime that reads its operands from memory and allocates its result; the runtime is a separate object, so LLVM cannot join two operators. Adding more operators to that loop (the request of libs as written) keeps the same shape: twelve operators of a quarter round are twelve passes over memory and twelve allocations.

## The design (what a Tensor must be)
- **D1. The element type is the machine type.** `Tensor[U8|U16|U32|U64]` stores elements of that width and its `+ - * shl rotl` wrap at that width. `Tensor[U32]` rotates in 32 bits. This removes every mask of the library.
- **D2. An element-wise expression is one loop, written in the program's own IR.** `((a_i + b_i) xor d_i) rotl 16`, of any depth and with scalar operands, lowers to a single loop over untagged words with no call inside: operands are read once, the result is written once. Rotations are `llvm.fshl`/`llvm.fshr`. The loop vectoriser of LLVM then makes the vector instructions of the machine; this is where the factor 8 to 16 comes from, and it is the compiler doing it, not us.
- **D3. A tensor of fixed small shape is a value, not a block of memory.** `Tensor[U32 * 16]` whose shape is known and that does not escape is the LLVM type `<16 x i32>`: one register. A sequence of statements over such tensors (a quarter round) then keeps everything in registers between statements (reason 2), which D2 alone cannot give across statements.
- **D4. No allocation when the result replaces an operand.** `a_i = a_i + b_i`, or an operand at its last use (the ownership rule the language already has), writes in place.
- **D5. Selection by constant indices is a `shufflevector`**; by a tensor of indices it is a gather loop. For ChaCha20 it is not even needed: with one tensor per state word (16 tensors of N blocks) the diagonal round only names other tensors.
- **D6. Wide products.** `U32 x U32 -> U64` element-wise (vectorises; this is how vector Poly1305 works with 26-bit limbs) and scalar `U64 x U64 -> (hi, lo)` (`mul i128` in IR; one instruction).
- **D7. Typed scalars.** Inside a function, a scalar of type `U32`/`U64` is an untagged machine integer. This is TASK-0082 (typed lowering); the loops of D2 need it for their scalar operands and the scalar parts of Poly1305 need it everywhere.
- **D8. The machine's vector width.** The same IR gives SSE2, AVX2 or AVX-512 code according to the target features given to LLVM. The build chooses: the host's features, or a portable baseline. Several copies chosen at start is a later step.

The library then writes ChaCha20 over N blocks at once: 16 tensors `Tensor[U32 * N]`, one per state word, and the quarter round as four statements. That is the kernel's algorithm, and with D1 to D4 it compiles to the same instructions.

## What this cannot reach without target-specific instructions
- Carry-less multiplication (GHASH) and the AES round have no portable form in LLVM IR that I know of in the installed version; they exist as target intrinsics (`llvm.x86.pclmulqdq`, `llvm.x86.aesni.*`), which are not assembly but are per target, with a slow portable fallback. ChaCha20-Poly1305 needs neither.
- The pure x86-64 encoder and WebAssembly get the same loops without vector instructions: correct, slower.

## Consequence for the request of libs (TASK-0104)
Its points 1 to 5 are implemented as D1 + D2 (one fused loop in the program), not as more cases of the runtime loop. Point 6 is D5, point 7 is D6, point 8 is the target intrinsic above.

## Plan
- [x] D1: element width by type (storage and wrap): `U8`, `U16`, `U32` packed; signed sized types not yet (1.0.37)
- [x] D2: fused element-wise loop in the program IR, scalar operands, one dimension, broadcast (1.0.37)
- [x] D4: in place when the operand dies and has one owner (1.0.37)
- [ ] D3: fixed small shapes as LLVM vectors. Done instead in 1.0.37: consecutive statements run as one loop, so values stay in registers between statements of one block; not across calls
- [ ] D5, D6
- [x] D8: three versions of each loop (plain, AVX2, AVX-512) chosen when the program runs (1.0.37)
## Progress log (append-only, newest last)
- 2026-11-18: design written by reasoning from what the kernel code is; nothing implemented.
- 2026-11-19: D1, D2, D4, D8 and the joining of statements implemented in 1.0.37 (FR-COMP-031, `docs/etc/fused_elementwise.md`). Measured: the ChaCha20 quarter round on 64 blocks, 97 ns as one loop (360 ns as eight calls). The fixed cost of a fused call is 24 ns; with several results the tuple adds to it.
- 2026-11-19: 1.0.38 adds `mulhi`, `clmul`, `clmulhi`, selection by index and `tensor sum/min/max`. ChaCha20 (20 rounds) on 64 blocks at once, written with 16 `Tensor[U32 * n]` and each double round as one block of statements: 8.8 µs for the key stream of a 4096-byte page, the result of RFC 8439 2.3.2. The loops are no longer the cost: about 5 µs are the fixed cost of ten fused calls with 16 results each. Next for this task: that fixed cost (open the leaves and give the results without a tuple), and D3.
- 2026-11-19: 1.0.39: a fused step that a function repeats by calling itself runs inside one fused call (`fuse repeat case`), and element reads and writes of `U16`/`U32` are in line. ChaCha20 on 64 blocks: 4.4 µs for the key stream of a page (the ten double rounds 1.75 µs). Left: D3 for steps done once, and the cost of making tensors.
- 2026-11-19: 1.0.40: `tensor bytes`, `tensor u16/u32 from bytes` and `tensor interleave`. A whole page of 4096 bytes encrypted with ChaCha20, bytes in and bytes out: 5.6 µs, checked against an implementation written apart and RFC 8439 2.4.2. `tensor interleave` is about 1 µs of it (a loop with a stride, not vectorised).
## Decisions / open questions
- D7 depends on TASK-0082.
- D8: host features or portable baseline as the default of `stable build`.
