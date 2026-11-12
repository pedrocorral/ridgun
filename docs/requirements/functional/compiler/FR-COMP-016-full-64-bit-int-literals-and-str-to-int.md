---
id: FR-COMP-016
title: Full 64-Bit Int Literals and str_to_int (RG-113)
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-07
updated: 2026-11-07
depends_on:
  - FR-COMP-004
  - FR-COMP-011
verified_by: [TS-COMP-016]
---
# FR-COMP-016 — Full 64-Bit `Int` Literals and `str_to_int` (RG-113)

## Statement
`Int` is a 64-bit signed integer (`tutorials.md`: "`Int` - 64-bit integers"). Every way of writing or reading an `Int` SHALL produce all 64 bits, on every backend (LLVM, the pure x86-64 and ARM64 encoders, Mach-O 64 and PE32+):

1. **Decimal literals.** A decimal literal in `0 .. 9223372036854775807` SHALL have exactly its written value. Digit separators (`_`) and the unit suffixes (`_KB`, `_MB`, `_GB`, `_ms`, `_s`, `_min`) keep their meaning.
2. **Range errors.** A decimal literal above `9223372036854775807`, also after applying a unit suffix, SHALL be a compile error: `syntax error: integer literal '<text>' is out of range for Int (-9223372036854775808 .. 9223372036854775807) in function '<name>'`. The literal `9223372036854775808` SHALL be valid only directly after a unary minus, where it is the `Int` minimum; after a binary minus it SHALL be the same error.
3. **Hexadecimal literals.** A hexadecimal literal (`0x` / `0X`) SHALL be the 64-bit two's-complement bit pattern of its digits, so `0x8000000000000000` is `-9223372036854775808` and `0xFFFFFFFFFFFFFFFF` is `-1`. More than 16 significant hex digits SHALL be a compile error with the message of §2.
4. **`str_to_int`.** `str_to_int s` SHALL return the exact 64-bit value of `s` and keep its parsing rules: leading and trailing ASCII whitespace (bytes 9-13 and 32) is ignored, `_` is ignored anywhere, an optional `+` or `-` sign is accepted, a `0x` / `0X` prefix selects base 16 (its sign follows the prefix), and the result is `0` for text that is not a number or does not fit in `Int`.
5. **Literal patterns.** An `Int` literal pattern (`f 9223372036854775807 = ...`, `f -9223372036854775808 = ...`) SHALL match exactly the value it denotes.

## Implementation notes
- The lexer accumulates literal digits with 64-bit arithmetic instead of calling `str to int`; out-of-range literals become `TokBadInt` / `TokIntMin` tokens and the parser turns them into syntax errors.
- An immediate `Int` is tagged as `(n * 2) + 1` and holds only `-2^62 .. 2^62 - 1`. Wider literals are lowered as `(n / 2) * 2 + (n - (n / 2) * 2)` with `NBinOp`, whose result is heap-boxed (FR-COMP-011 OPT-008) on every backend.
- `str_to_int` calls are lowered to the compiler-provided helper `__rg_s2i_wide`: strings of at most 17 characters (always `|n| < 2^62`) still use the runtime builtin; longer strings are parsed with 64-bit arithmetic.

## Rationale
Before 0.9.34 the literal `9223372036854775807` compiled to `-1` and `str_to_int` returned wrong values for 19-digit strings, without any error (Solstice register RG-113). Programs worked around it by computing the maximum and by writing their own parsers.

## Acceptance Criteria
1. **AC-1**: `echo (int to str 9223372036854775807)`, `(-9223372036854775808)` and `4611686018427387904` print exactly those values, and literal patterns with those values match (`tests/cases/literals/rg113_int64_literals.ridgun`).
2. **AC-2**: `9223372036854775808`, `0 - 9223372036854775808`, a 17-digit hex literal and `9000000000_GB` fail to build with `integer literal '<text>' is out of range for Int` (`tests/cases/literals/rg113_*_fails.ridgun`, `rg113_int_min_magnitude_needs_unary_minus.ridgun`).
3. **AC-3**: `str_to_int` returns `9223372036854775807`, `-9223372036854775808` and every 19-digit value exactly, returns `0` for `9223372036854775808` and invalid text, and gives the same results through `map str to int` (`tests/cases/strings/rg113_str_to_int_64bit.ridgun`).
