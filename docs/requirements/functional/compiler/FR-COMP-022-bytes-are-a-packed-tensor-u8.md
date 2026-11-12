---
id: FR-COMP-022
title: Bytes Are a Packed One-Dimensional Tensor[U8]
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-09
updated: 2026-11-09
depends_on: [FR-COMP-018, FR-COMP-020]
related: [FR-COMP-023]
verified_by: [TS-COMP-022]
---
# FR-COMP-022 — Bytes Are a Packed One-Dimensional Tensor[U8]

## Statement
Binary data in Ridgun SHALL be a one-dimensional `Tensor[U8]` (`Byte` is the same type), stored one byte per element, as arrays of bytes are in other languages (`[]byte`, `Vec<u8>`, `bytearray`, `Uint8Array`). Every builtin that reads, writes, hashes, checksums or passes binary data to the system SHALL take or return a `Tensor[U8]`. Lists of `Int` are not a byte format.

## Requirements
1. **Packed storage.** A `Tensor[U8 * n]` or `Tensor[Byte * n]` stores its `n` elements as `n` contiguous bytes. This replaces, for these two element types, the "one 64-bit number per element" rule of FR-COMP-018 §1. Two- and more-dimensional `U8` tensors are packed too.
2. **Element values.** Reading an element gives an `Int` in 0..255. Writing an `Int` outside 0..255 stops the program with `runtime error: U8 element out of 0..255` on stderr and exit status 1. Writes are in place (OPT-005), with no allocation.
3. **Conversions with String.**
   ```ridgun
   fn :: tensor from str String => Tensor[U8]   -- the bytes of the String
   fn :: tensor to str Tensor[U8] => String     -- the bytes as a String
   fn :: tensor u8 from list [Int] => Tensor[U8] -- fixed bytes: headers, test vectors, keys
   ```
   Each conversion makes one allocation and copies the bytes once. Any byte 0..255 is allowed, including bytes that UTF-8 never uses. `tensor u8 from list` stops the program, as an element write does, when a value is outside 0..255.
4. **Files.** `read bytes path => Tensor[U8]` replaces the `[Int]` form. `write bytes path Tensor[U8] => ()` also accepts a `[Int]` of values 0..255 while the compiler writes its own output with it (stage 1 of the bootstrap is built by the previous compiler). `read bytes` returns every byte of the file, also when the file has no size: a pipe (`/dev/stdin` fed by `|`), a terminal or a procfs file. It reads such a file once, to its end, because a pipe cannot be read twice.
5. **File descriptors.** Besides the String forms, `sys read into fd t from count => Int` reads up to `count` bytes into `t` starting at index `from`, without allocating, and returns the number of bytes read (or a negative errno); `sys write from fd t from count => Int` writes `count` bytes of `t` starting at `from`.
6. **System calls with buffers.** An argument of `sys call` may be a `Tensor[U8]`: the kernel receives the address of its first byte. The tensor stays alive and is not moved during the call. This lets a library read results that the kernel writes into memory (`clock_gettime`, `stat`, `getrandom`, socket addresses).
7. **Hashes.** `sha256 raw` also accepts a `Tensor[U8]`, and `sha256 digest` of a `Tensor[U8]` or a `String` returns the 32-byte digest as a `Tensor[U8 * 32]`.
8. **CRC-32.** `crc32 range data from to crc => Int` accepts a `Tensor[U8]` or a `String` as `data`. It returns the CRC-32 (IEEE 802.3, reflected polynomial `0xEDB88320`, as zlib and gzip) of the bytes `from` to `to - 1`, without copying them, in 0..4294967295. `crc` is `0` to start or the result of the previous call: `crc32 range s m n (crc32 range s 0 m 0)` equals `crc32 range s 0 n 0`. `crc32 range "123456789" 0 9 0` is `3421780262`. Unless `0 <= from <= to <=` the length, the program stops with `runtime error: crc32 range: range out of bounds` and exit status 1.
9. **Speed.** Byte loops cost what they cost in C, give or take the bounds check: `crc32 range` 100 MB in under 0.5 s; `tensor to str` of 4 bytes, 1,000,000 times in under 1 s.
10. **Backends.** One implementation in the shared runtime where possible, used by LLVM and the pure x86-64 encoder. ARM64 follows when its runtime has tensors.

## Rationale
Binary formats (TLS, PostgreSQL, the Eterval log) build frames byte by byte, write them, read them back and check them. The natural tool is a fixed-size byte array written in place. A list of `Int` uses 8 bytes per element, has list semantics (grow, walk) instead of buffer semantics, and must still be converted before any I/O. libs asked for `str from bytes [Int]` (report `reloj-bytes-crc32`, 2026-11-08); the byte array makes that function unnecessary.

## Out of scope
- Packing of other fixed-width element types (`U16`, `U32`, `I8` ... ): same principle, separate requirement.
- Zero-copy views between `String` and `Tensor[U8]`.

## Typing
`U8` and `Byte` in element position are their own type. A `Tensor[U8]` is compatible only with another `Tensor[U8]`: not with `Tensor[Int]`, a bare `Tensor` or `Tensor[T]`. `@`, element-wise and bitwise operators, row and column slices and maps over a `Tensor[U8]` are compile errors. A `Tensor[U8]` that is indexed, shown, hashed or turned into a list is a variable, a function call, a typed allocation or a copy `t_ij`; any other expression must first be bound to a variable (compile error otherwise).

## Implementation status
Implemented in 0.9.48 (TASK-0063): one shared runtime routine for both backends (`docs/etc/runtime_ext.md`, builtins 103-118), with inline LLVM fast paths for one-dimensional reads and writes. Tests: `tests/cases/tensors/bytes_*.ridgun`, `tests/cases/perf/bytes_crc32_and_conversions.ridgun`.

0.9.50 (TASK-0065, libs report `tensor-u8`): `tensor u8 from list`; a shape pattern binds the right dimensions also when the tensor is `_` or has no name; a `Tensor[U8]` bound inside a constructor, list cons, tuple or `Some` pattern is read by bytes. Tests: `bytes_from_list*.ridgun`, `bytes_shape_pattern_without_name.ridgun`, `bytes_in_constructor_pattern.ridgun`.

Known limit: `echo` of a list, tuple or record that holds a `Tensor[U8]` shows the tensor's storage words; `echo t` on the tensor shows its elements.
