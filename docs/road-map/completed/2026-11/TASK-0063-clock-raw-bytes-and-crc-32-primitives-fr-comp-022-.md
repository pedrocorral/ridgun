---
id: TASK-0063
title: Bytes as a packed Tensor[U8] and fast clocks (FR-COMP-022, FR-COMP-023, libs)
status: completed
created: 2026-11-09
completed: 2026-11-09
requirements: [FR-COMP-022, FR-COMP-023]
tests: [TS-COMP-022, TS-COMP-023]
security: []                # VUL-* to address
context_files: [docs/requirements/functional/compiler/FR-COMP-022-bytes-are-a-packed-tensor-u8.md, docs/requirements/functional/compiler/FR-COMP-023-fast-clocks-through-the-vdso.md, docs/etc/gentensor.md, src/main/ridgun/lib/llvm.rg, src/main/ridgun/lib/x86_64.rg, src/main/ridgun/lib/compiler.rg]
scope: [src/main/ridgun/lib/, docs/etc/gentensor.md, tests/cases/]
owner: agent-001
claimed: 2026-11-09T14:04:54Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0063 — Bytes as a packed Tensor[U8] and fast clocks (FR-COMP-022, FR-COMP-023, libs)

## Goal (one sentence)
Binary data is a packed one-dimensional `Tensor[U8]` across every byte builtin, and the clocks read the vDSO, as FR-COMP-022 and FR-COMP-023 describe (answer to the libs report `reloj-bytes-crc32`, 2026-11-08).

## Plan
- [x] Inventory every tensor operation that assumes 8-byte elements (compiler, LLVM helpers, x86-64 routines, runtime) and decide the packed representation (own heap tag or element-width field).
- [x] Packed `Tensor[U8]`: allocation, read, in-place write with the 0..255 check, shape patterns, `tensor to list`, show, equality (no `tensor from list` to `U8`: FR-COMP-022 does not use lists as a byte format; build with `tensor from str` or element writes); every other operation either supports it or is a compile error.
- [x] `tensor from str`, `tensor to str`; `read bytes` / `write bytes` on `Tensor[U8]`; `sys read into`, `sys write from`; `sys call` with `Tensor[U8]` arguments.
- [x] `sha256 raw` on `Tensor[U8]`, `sha256 digest`; `crc32 range` on `Tensor[U8]` and `String`.
- [x] Clocks: vDSO found from the auxiliary vector at start, one runtime routine for the three clocks.
- [x] Tests, docs (spec, FR-COMP-018 §1 note), bootstrap, suites with memory caps, install, 0.9.48; notice to libs.

## Progress log (append-only, newest last)
- 2026-11-09: Measured on the reference machine: `clock_gettime` system call 321 ns, vDSO 17 ns.
- 2026-11-09: First approach (four builtins written twice, LLVM IR and x86-64 assembly, `str from bytes [Int]`) dropped before commit: the ideal is one shared implementation and bytes as a byte array, not a list. Requirements rewritten as FR-COMP-022 and FR-COMP-023. The LLVM IR drafts (clock, CRC slicing-by-8, vDSO lookup) are kept in the working tree for reuse.

- 2026-11-09: Inventory done (see "Inventory" below). Representation decided (see Decisions).
- 2026-11-09: Runtime extension (one C file, 10128 bytes) appended to the shared runtime; byte tensors, CRC-32, SHA-256 digest, buffered fd and `sys call`, clocks. Inline LLVM fast path for 1-D reads and writes (164 -> 33 ms per 10M reads once the slow path takes values, not the frame address). `sha256 digest` decodes the hex of runtime builtin 21: runtime builtin 36 is not the raw digest.

- 2026-11-09: `write bytes` now rejects list elements outside 0..255 instead of keeping the low byte. That exposed `u64 le` (`elf64.rg`): for a negative value below -2^32 it gave numbers outside 0..255, so the x86-64 encoder wrote a wrong immediate (the known `rg113_int64_literals` failure on x86-64 since 0.9.46). All little-endian encoders now give the two's complement bytes of any `Int`.
- 2026-11-09: Tests that used `Tensor[Byte]` as "some numeric tensor" (`gen_tensor_shape_patterns.rg`, `test parallel and tensors.rg`) or `read bytes` as a list (`test strings.rg`, `test cross platform targets.rg`) follow FR-COMP-022: `Tensor[Int]` where any numeric tensor was meant, a separate `Byte` shape helper, `tensor to list (read bytes ...)`, and direct indexing `bytes_(i)`.

## Inventory: what assumes 8-byte elements
- **Shared runtime (machine code in `x86_64.rg`, used by both backends):** index (rt 38), index set (rt 39), einsum (rt 40), hadamard (rt 41), sequence select (rt 42), echo and value-to-string, deep equality, the copy of builtin 90 op 12 (`t_` and copies on send), drop and clone (element-agnostic: they free or count buffers). The runtime cannot be edited in place: its routines sit at fixed addresses, and at least one routine jumps through a per-tag table without a bounds check, so a new heap tag is unsafe.
- **Compiler-emitted code:** `NIndex`/`NIndexSet` fast paths (LLVM `@__rg_tensor_index_*`, x86 `idxset1.s`/`idxset2.s`/`bounds.s`), `NCallBuiltin 88` (fill), `NGtConv` modes 1-4, builtins 89-95 (bitops, row/column slices and writes), `@__rg_fast_einsum*`, shape patterns and `NAdtField b (-10 - k)` (dimensions).
- **Type checker:** every integer width (`U8`, `Byte`, ...) is `TyInt`, so `Tensor[U8]` and `Tensor[Int]` are the same type today; a bare `Tensor` or `Tensor[T]` parameter accepts any tensor.
- **Builtins with byte data:** `read bytes` / `write bytes` (`[Int]`; the compiler itself writes its output with `write bytes [Int]`), `sha256 raw` (String), `sys read fd` / `sys write fd` (String), `sys call` (Int arguments only).

## Files changed (keep current)
- Requirements: `FR-COMP-022-bytes-are-a-packed-tensor-u8.md`, `FR-COMP-023-fast-clocks-through-the-vdso.md`, FR-COMP-018 §1 note, compiler INDEX.
- Compiler: `x86_64.rg` (runtime extension blob at 4289168, builtin ids >= 100), `llvm.rg` (`@__rg_rt_ext`, inline `U8` read/write helpers; old clock/CRC IR drafts removed), `typecheck.rg` (`U8` element type and builtin types), `parser.rg` (arities), `compiler.rg` (builtin ids, kind `B` lowering), version 0.9.48 in `build.rg`, `ridgunc/main.rg`, `stable/main.rg`.
- Docs: `docs/etc/runtime_ext.md` (new: C source, linker script, build), `docs/etc/INDEX.md`, `docs/etc/gentensor.md`, `docs/lang/spec.md`, book chapter 08 (8 languages), Ridgun skill.
- `elf64.rg`: `u16 le` / `u32 le` / `u64 le` give two's complement bytes for any `Int` (`le bytes`).
- Existing tests adapted: `tests/cases/tensors/gen_tensor_shape_patterns.rg`, `src/test/ridgun/test parallel and tensors.rg`, `test strings.rg`, `test cross platform targets.rg`.
- Tests: `tests/cases/tensors/bytes_*.rg` (5), `tests/cases/perf/bytes_crc32_and_conversions.rg`, `tests/cases/runtime/clocks_through_the_vdso.rg`.

## Verification performed (command → result, newest last)
All runs capped (`ulimit -v` 4 GB, timeout).
- Runtime extension, native harness (`rtx.c` with stub runtime): CRC-32 equal to zlib on random data and chained ranges; SHA-256 digest equal to `sha256sum`.
- Stage 1 on both backends: `bytes_are_a_packed_tensor_u8.rg` identical output; runtime errors (U8 range, index out of range, crc bounds) exit 1 with their messages; type errors as expected.
- Speed, LLVM / x86-64: `crc32 range` 100 MB 60 / 61 ms; `tensor to str` 4 bytes x 1M 67 / 133 ms; clock x 1M 28 / 67 ms; U8 reads x 10M 33 / 614 ms (Int reads 40 / 1183 ms).
- Bootstrap bin/ridgunc (0.9.47) -> s1 -> s2 -> s3 -> s4 (0.9.48): s3/s4 differ by 3 bytes (the `__rg_llvm_<pid>.ll` temporary name). Self-build peak 947 MB, 136 s, the same as the installed 0.9.47.
- `RIDGUNC=s3 STABLE=stable_n ridgunc run tests/run.rg`: 244 of 244 (LLVM 126 of 126, x86-64 118 of 118, toolchain checks included).
- `test basics`, `test core language`, `test strings`, `test parallel and tensors`, `test llvm codegen`: pass on LLVM and x86-64. `test cross platform targets`: only its known `lower_sample_prog` type error, as on 0.9.47.
- Installed `bin/ridgunc` and `bin/stable` 0.9.48 from `target/` candidates; the installed compiler builds and runs the bytes case.

## Exact next actions
None.

## Decisions / open questions
- **Type.** In element position `U8` and `Byte` give a distinct element type (`TyVar "U8"`, kind `B`). `Tensor[U8]` is compatible only with `Tensor[U8]`/`Tensor[Byte]`: not with `Tensor[Int]`, a bare `Tensor` or `Tensor[T]`. So every operation on a packed tensor is known at compile time. Reading an element gives `Int`; writing takes `Int`.
- **Layout.** Heap tag 5 (numeric tensor), so drop and clone work unchanged. The shape vector is `[W]` and the data vector holds `W` 64-bit words: word 0 = rank `k`, words 1..k = the dimensions, then the `N` bytes packed, zero padded. To any runtime routine the value is a valid one-dimensional numeric tensor of `W` words, so nothing it does can read outside the buffer; deep equality and the `t_` / send copy are exact (they compare or copy every word, dimensions included).
- **One implementation.** The byte-tensor operations, `crc32 range` and the clocks are one C source compiled to position-independent machine code and appended to the shared runtime (`x86 rt ext`), entry `rg_rtx(id, slots, count)`. Builtin ids 100 and up call it from both backends (LLVM: linker-script symbol `__rg_rt_ext`). The C source and the build commands live in `docs/etc/runtime_ext.md`.
- **Unsupported operations on `Tensor[U8]`** (`@`, element-wise operators, bitwise operators, row/column slices, map rows/columns/elements) are compile errors.
- **Bootstrap.** The compiler writes its own output with `write bytes [Int]`, and stage 1 is built by the previous compiler, so `write bytes` accepts `[Int]` or `Tensor[U8]` in this release. `read bytes` returns `Tensor[U8]`.
- Writing an `Int` outside 0..255 to a `U8` element is a runtime error (no silent truncation).
- `crc32 range` checks `0 <= from <= to <= length` and stops with a runtime error otherwise.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated (none: no new attack surface beyond `sys call`, which already took raw addresses)  - [x] docs INDEX updated  - [x] coverage matrix regenerated (not kept in this project: no docs/tests/coverage-matrix.md)
