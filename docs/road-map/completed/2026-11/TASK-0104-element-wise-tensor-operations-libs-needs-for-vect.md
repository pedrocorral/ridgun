---
id: TASK-0104
title: Element-wise tensor operations libs needs for vector crypto (shifts with scalar, U32 wrap, U8, one dimension, gather, wide and carry-less multiply)
status: completed
created: 2026-11-18
completed: 2026-11-19
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner: agent-001
claimed: 2026-11-18T22:23:02Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0104 — Element-wise tensor operations libs needs for vector crypto

## Goal (one sentence)
Give the libraries the tensor operations of their request `/tmp/ridgun-compiler/2026-11-18/tensor-ops-para-cripto.md` (8 points), built on the design of TASK-0103.

## Plan
- [x] 1. `shl shr rotl rotr` element-wise, tensor with tensor and tensor with a number, vectorised (1.0.37)
- [x] 2. A number as an operand (1.0.37)
- [x] 3. Arithmetic that wraps at 32 bits: `Tensor[U32]` (and `Tensor[U16]`) packed (1.0.37)
- [x] 4. `xor and or` (and the other operators) on `Tensor[U8]` (1.0.37)
- [x] 5. One-letter subscripts and tensors along the first or last dimensions (1.0.37)
- [x] 6. Selection of elements by index: `t_(index)` (1.0.38)
- [x] 7. Wide multiplication: `mulhi` at the width of the type, with `*` the whole product (1.0.38)
- [x] 8. Carry-less multiplication: `clmul`, `clmulhi` (1.0.38)
- [x] Reductions inside an expression: `tensor sum`, `tensor min`, `tensor max` (1.0.38)
## Progress log (append-only, newest last)
- 2026-11-19: points 1 to 5 in 1.0.37 as FR-COMP-031: the `:fuse:` node, `core/fuse.ll`, `llvm fuse fn`, packed `U16`/`U32`, joined statements, results in place, three vector versions. The eight repro files of the request build and give the expected values (`w1` now wraps at 2^32).
- 2026-11-19: points 6, 7 and 8 and the reductions in 1.0.38. The element kinds left the program text: `NHadamard (1000 + kinds)`, one digit per tensor, so one expression can read tensors of several element types. `clmul` checked against a bit-by-bit reference written apart; the operator matrix has 373 rows (every integer operator on U8, U16, U32, U64).
## Files changed (keep current)
- `src/main/ridgun/lib/ast.ridgun`, `parser.ridgun`, `typecheck.ridgun`, `analyzer.ridgun`, `compiler.ridgun`, `llvm.ridgun`; generated `x86rt.ridgun`, `x86flat.ridgun`, `wasmrt.ridgun`, `llvminl.ridgun`
- `src/main/runtime/core/fuse.ll` (new), `bytes.ll`, `tensor.ll`
- `tests/cases/tensors/fused_*.ridgun`, `packed_u16_and_u32_*.ridgun`, `elementwise_*.ridgun`, `u32_element_out_of_range_exits.ridgun`; `tests/runtime/run-fuse-levels.sh`
- `docs/requirements/functional/compiler/FR-COMP-031-*.md`, `docs/etc/fused_elementwise.md`, `docs/lang/spec.md`
## Verification performed (command → result, newest last)
- See the commit of 1.0.37.
## Exact next actions
1. Nothing left of the request. Open, from use: a copy of a `Tensor[U8]` as a `Tensor[U32]` and back (the words of a block of bytes), and joining statements that select by index.
## Decisions / open questions
- Scalar writes into a packed element outside its range stop the program, as for `U8`; only element-wise arithmetic wraps.
