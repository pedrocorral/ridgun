---
id: FR-COMP-033
title: "`siphash13 range`: SipHash-1-3 of a range of bytes"
status: implemented
priority: should
created: 2026-11-19
updated: 2026-11-19
depends_on: []
related: []
verified_by: []
---
# FR-COMP-033 — `siphash13 range`: SipHash-1-3 of a range of bytes

## Statement
1. `siphash13 range key data from to` is the SipHash-1-3 (Aumasson and Bernstein; 1 compression round, 3 finalisation rounds) of the bytes `from .. to - 1` of `data`, as an `Int` of 64 bits. `key` and `data` are a `String` or a `Tensor[U8]`.
2. The key is 16 bytes: `k0` is bytes 0–7 and `k1` bytes 8–15, little-endian. The result is `v0 xor v1 xor v2 xor v3`.
3. `siphash13 range low key data from to` is the low 32 bits of that value.
4. A key that is not 16 bytes, or a range outside the data, gives 0.
5. The result is the same on every target and in every version: programs keep keys on disk.

## Rationale
A hash table whose keys a client chooses needs a keyed hash. In Ridgun code SipHash-1-3 of a 25-byte key takes about 2000 ns (libs, 2026-11-19); it is short scalar work, so tensors do not help.

## Acceptance Criteria
1. **AC-1**: with the key `00 01 .. 0f` and the input `00 01 .. n-1`, the values for n = 0, 1, 7, 8, 15, 16, 25, 64 are `abac0158050fc4dc`, `c9f49bf37d57ca93`, `d3927d989bb11140`, `369095118d299a8e`, `d320d86d2a519956`, `cc4fdd1a7d908b66`, `45cd5928705b0979`, `f17997ec4b4a6065`.
2. **AC-2**: a range in the middle of the data gives the value of those bytes alone; a `Tensor[U8]` gives the same as the `String` of its bytes.
3. **AC-3**: `siphash13 range low` gives `705b0979` for n = 25.
4. **AC-4**: a key of 5 bytes gives 0; `to` past the data and `from > to` give 0.
5. **AC-5**: the WebAssembly back end gives the same output.

Case: `tests/cases/strings/siphash13_range_matches_the_reference.ridgun`.
