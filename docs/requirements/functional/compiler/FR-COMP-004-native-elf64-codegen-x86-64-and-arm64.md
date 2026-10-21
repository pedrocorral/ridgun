---
id: FR-COMP-004
title: 100% Pure-Ridgun Native ELF64 Code Generation for x86_64 and ARM64 Without Rust or rustc
status: implemented
priority: must
created: 2026-10-21
updated: 2026-10-21
depends_on:
  - FR-COMP-001
  - FR-COMP-002
  - FR-COMP-003
verified_by: []
---
# FR-COMP-004 — 100% Pure-Ridgun Native ELF64 Code Generation for `x86_64` and `ARM64` Without Rust or `rustc`

## Statement
The `ridgunc` compiler and the Ridgun repository SHALL be 100% self-contained in pure Ridgun (`.rg`) with zero Rust source files (`.rs`), zero `Cargo.toml`/`Cargo.lock` manifests, and zero invocations of `rustc` or any external C/Rust compiler:
1. **Direct ELF64 Binary Emission (`src/main/ridgun/lib/elf64.rg`)**:
   - `ridgunc build` and `ridgunc run` SHALL emit standalone Linux ELF64 executables directly to disk via `write_bytes` without invoking `rustc`, `gcc`, `cc`, or `ld`.
   - The ELF64 emitter SHALL support both Linux `x86_64` (`e_machine = EM_X86_64 = 62`) and Linux `ARM64` / `AArch64` (`e_machine = EM_AARCH64 = 183`, Raspberry Pi 3/4/5).
2. **Native Machine-Code Backends (`src/main/ridgun/lib/x86_64.rg` and `src/main/ridgun/lib/arm64.rg`)**:
   - All reachable Ridgun functions (`fn ::` and `op ::`), pattern matches, guards (`|`, `|.`), parallel DAG `where` blocks (`||`, `||.`), mutable bindings (`mut`), tail-call loops (TCO), and `RMM1`/`RMM2` memory management operations SHALL be compiled directly into native `x86_64` or `ARM64` machine instructions.
   - All runtime primitives (`Int`, `Real`, `String`, `Bool`, `List`, `Tuple`, `Adt`, `Tensor`, `einsum`, Hadamard `@+`/`@-`/`@*`/`@/`, `map`, `||map`, `filter`, `||filter`, `fold`, channels/mailboxes, `context`/`shared`/`atomic`, `with region`, and POSIX/Linux OS built-ins) SHALL be embedded directly as native machine code inside the ELF64 binary.
3. **Complete Elimination of Legacy Rust Code**:
   - The legacy `src/main/rust/` directory, `Cargo.toml`, and `Cargo.lock` SHALL be removed from the repository.
   - `src/main/ridgun/lib/compiler.rg` SHALL contain zero embedded Rust source code and zero `rustc` shell commands.

## Rationale
- Eliminating the intermediate Rust transpilation step and `rustc` dependency makes Ridgun a 100% self-hosted native compiler, reduces executable link/emission time from ~30s to milliseconds, supports cross-compilation to `ARM64` (Raspberry Pi) out of the box, and removes all non-Ridgun source code from the project.

## Acceptance Criteria
1. **AC-1 (Zero Rust / Zero `rustc`)**: No `.rs` files, `Cargo.toml`, or `rustc` invocations remain anywhere in `src/` or the repository root.
2. **AC-2 (Self-Hosting Stage 1 & Stage 2)**: `target/ridgunc` compiles `src/main/ridgun/ridgunc/main.rg` and `src/main/ridgun/stable/main.rg` into native ELF64 executables (`Stage 1`), and `Stage 1` recompiles them into identical `Stage 2` native ELF64 executables without `rustc`.
3. **AC-3 (Full Language & Test Suite Parity)**: `./target/stable check`, `./target/stable test` (all 4 test suites: `test_basics.rg`, `test_core_language.rg`, `test_parallel_and_tensors.rg`, `test_strings.rg`), and `./target/stable format` pass with 0 errors.
4. **AC-4 (`x86_64` and `ARM64` ELF64 Target Support)**: `ridgunc build` supports emitting both `x86_64` (`EM_X86_64 = 62`) and `ARM64` (`EM_AARCH64 = 183`) ELF64 binaries.
