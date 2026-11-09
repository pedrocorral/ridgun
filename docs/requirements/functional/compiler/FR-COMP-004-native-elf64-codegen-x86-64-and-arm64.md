---
id: FR-COMP-004
title: 100% Pure-Ridgun Native ELF64 Code Generation for x86_64 and ARM64 Without Rust or rustc
status: implemented
priority: must
created: 2026-10-21
updated: 2026-11-09
depends_on:
  - FR-COMP-001
  - FR-COMP-002
  - FR-COMP-003
verified_by: []
---
# FR-COMP-004 — 100% Pure-Ridgun Native ELF64 Code Generation for `x86_64` and `ARM64` Without Rust or `rustc`

## Statement
The `ridgunc` compiler and the Ridgun repository SHALL be 100% self-contained in pure Ridgun (`.rg`) with zero Rust or C source files (`.rs`, `.c`), zero `Cargo.toml`/`Cargo.lock` manifests, and zero invocations of `rustc`, `clang`, or `gcc`:
1. **Native ELF64 Binary Emission (`src/main/ridgun/lib/llvm.rg` and `src/main/ridgun/lib/elf64.rg`)**:
   - `ridgunc build` and `ridgunc run` SHALL emit standalone Linux ELF64 executables without invoking `rustc`, `clang`, or `gcc` (using pure LLVM IR `.ll` compiled via `llc -O2 -filetype=obj` and linked via `ld` on `x86_64` per `ADR-0002`, and direct `elf64.rg` emission on `ARM64`).
   - The native backend SHALL support both Linux `x86_64` (`e_machine = EM_X86_64 = 62`) and Linux `ARM64` / `AArch64` (`e_machine = EM_AARCH64 = 183`, Raspberry Pi 3/4/5).
2. **Native Codegen Backends (`src/main/ridgun/lib/llvm.rg`, `src/main/ridgun/lib/x86_64.rg`, and `src/main/ridgun/lib/arm64.rg`)**:
   - All reachable Ridgun functions (`fn ::` and `op ::`), pattern matches, guards (`|`, `|.`), parallel DAG `where` blocks (`||`, `||.`), mutable bindings (`mut`), tail-call loops (TCO), and `RMM1`/`RMM2` memory management operations SHALL be compiled directly into native `x86_64` or `ARM64` machine instructions.
   - All runtime primitives (`Int`, `Real`, `String`, `Bool`, `List`, `Tuple`, `Adt`, `Tensor`, `einsum`, Hadamard `@+`/`@-`/`@*`/`@/`, `map`, `||map`, `filter`, `||filter`, `fold`, channels/mailboxes, `context`/`shared`/`atomic`, `with region`, and POSIX/Linux OS built-ins) SHALL be embedded directly as native machine code inside the ELF64 binary.
3. **Tail Calls in Constant Memory (`OPT-002`, `OPT-019`)**:
   - A call in tail position (the last expression of a function body, a block, a guard branch or a `where` body) SHALL reuse the caller's frame, so a chain of such calls runs any number of rounds in constant stack and memory. This holds for a function that calls itself (`OPT-002`) and for calls to other functions with all their arguments, including cycles of two or more functions (`OPT-019`).
   - A unit function (`=> ()`) whose last expression calls another unit function SHALL keep that call in tail position.
   - Limits: on LLVM, a caller or callee with more than 8 parameters, and on the x86-64 encoder a callee with more than 32 parameters, gets a plain call followed by a return. The ARM64 encoder does not reuse the frame for calls to other functions yet (one frame per round).
4. **Complete Elimination of Legacy Rust Code**:
   - The legacy `src/main/rust/` directory, `Cargo.toml`, and `Cargo.lock` SHALL be removed from the repository.
   - `src/main/ridgun/lib/compiler.rg` SHALL contain zero embedded Rust source code and zero `rustc` shell commands.

## Rationale
- Eliminating the intermediate Rust transpilation step and `rustc` dependency makes Ridgun a 100% self-hosted native compiler, reduces executable link/emission time from ~30s to milliseconds, supports cross-compilation to `ARM64` (Raspberry Pi) out of the box, and removes all non-Ridgun source code from the project.

## Acceptance Criteria
1. **AC-1 (Zero Rust / Zero `rustc`)**: No `.rs` files, `Cargo.toml`, or `rustc` invocations remain anywhere in `src/` or the repository root.
2. **AC-2 (Self-Hosting Stage 1 & Stage 2)**: `target/ridgunc` compiles `src/main/ridgun/ridgunc/main.rg` and `src/main/ridgun/stable/main.rg` into native ELF64 executables (`Stage 1`), and `Stage 1` recompiles them into identical `Stage 2` native ELF64 executables without `rustc`.
3. **AC-3 (Full Language & Test Suite Parity)**: `./target/stable check`, `./target/stable test` (all 4 test suites: `test_basics.rg`, `test_core_language.rg`, `test_parallel_and_tensors.rg`, `test_strings.rg`), and `./target/stable format` pass with 0 errors.
4. **AC-4 (`x86_64` and `ARM64` ELF64 Target Support)**: `ridgunc build` supports emitting both `x86_64` (`EM_X86_64 = 62`) and `ARM64` (`EM_AARCH64 = 183`) ELF64 binaries.
5. **AC-5 (Tail Calls Between Functions)**: `tests/cases/functions/mutual_tail_calls_3m.rg` (3 000 000 rounds between two functions, 3 000 000 between two unit functions, 1 000 000 turns of a three-function ring) prints the expected output with a peak resident memory below 64 MB, built for LLVM and for the x86-64 encoder (`--target x86_64-elf`).
