---
id: FR-VM-001
title: Verbatim File I/O and Raw Binary Byte-Stream Built-ins
status: implemented
priority: must
created: 2026-10-17
updated: 2026-10-17
depends_on: []
verified_by: []
---
# FR-VM-001 — Verbatim File I/O and Raw Binary Byte-Stream Built-ins

## Statement
The `ridgunc` runtime SHALL separate compiler `.rg` module `import` resolution (`load_rg_source`) from the general-purpose `read_file` built-in, preserve exact byte/line-ending fidelity (`\r\n` and EOF newline presence/absence) in `read_file`, and provide `read_bytes` / `write_bytes` for arbitrary raw binary streams (`0x00..0xFF`).

## Rationale
Discovered while implementing Tier 1 BSD utilities (`vis`, `unvis`, `lam`, `rs` in `unix-tools`):
1. Routing `read_file` through `rg_resolve_imports` corrupts arbitrary input files that happen to contain lines starting with `import <ident>` (turning them into `-- import <ident>` or splicing `.rg` files).
2. Implementing `read_file` via `BufRead::lines()` strips `\r` before `\n` (losing CRLF `0x0D 0x0A`) and unconditionally appends a trailing `\n` at EOF (turning a 9-byte file without a trailing newline into 10 bytes).
3. Byte-level filters (`vis`, `unvis`) must process arbitrary binary streams containing `0x00` (NUL) and non-UTF-8 bytes (`0x80..0xFF`).

## Functional Specification

### 1. Verbatim `read_file` vs Compiler `load_rg_source`
- **`read_file : String => String`**:
  - Reads the file at `path` (including `/dev/stdin`) verbatim using `std::fs::read_to_string` (or `std::io::Read::read_to_end` with lossless Latin-1/UTF-8 mapping), **never** invoking `rg_resolve_imports` and **never** using `BufRead::lines()`.
  - Exact `\r\n` sequences and the presence or absence of a trailing `\n` at EOF are preserved 100% intact.
- **`load_rg_source : String => String`** (internal compiler module loader):
  - Used exclusively by `ridgunc` and `stable` when loading `.rg` source files for compilation/typechecking so `import <module>` statements are recursively spliced.

### 2. Raw Binary Byte-Stream Built-ins
- **`read_bytes : String => [Int]`**:
  - Reads all raw bytes from `path` (or `/dev/stdin`) using `std::fs::read` and returns a Ridgun list `[Int]` where each element is an unsigned byte in `0..255`.
- **`write_bytes : String [Int] => ()`**:
  - Writes a Ridgun list of byte values (`0..255`) directly to `path` (or `/dev/stdout`) using `std::fs::write`.

## Acceptance Criteria
- AC1: Reading a file containing `import foo\n` via `read_file` returns `"import foo\n"` verbatim, not `"-- import foo\n"`.
- AC2: Reading a 9-byte file `"sin_salto"` (no trailing `\n`) via `read_file` returns a string of length `9`; reading `"hola\r\nmundo"` preserves `\r` (`char code 13`).
- AC3: `read_bytes` and `write_bytes` round-trip files containing `0x00` NUL bytes and `0x80..0xFF` bytes with 100% byte identity.
