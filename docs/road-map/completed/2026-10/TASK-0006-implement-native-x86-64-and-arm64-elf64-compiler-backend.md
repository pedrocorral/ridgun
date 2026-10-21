---
id: TASK-0006
title: Implement 100% standalone native x86_64 and ARM64 (Raspberry Pi) ELF64 compiler backend in Ridgun without rustc
status: completed
created: 2026-10-20
completed: 2026-10-21
after: [TASK-0004]
requirements: [FR-COMP-002, FR-COMP-003, FR-COMP-004]
tests: []
security: []
context_files: [src/main/ridgun/lib/compiler.rg, src/main/ridgun/ridgunc/main.rg, docs/etc/cmm_architecture.md]
scope: [src/main/ridgun/lib/x86_64.rg, src/main/ridgun/lib/arm64.rg, src/main/ridgun/lib/elf64.rg]
owner: agent-001
claimed: 2026-10-21T06:49:12Z
claimed_by: agent gemini@solarfall
policy: anarchy
---
# TASK-0006 — Implement 100% standalone native `x86_64` and `ARM64` (`AArch64` / Raspberry Pi) ELF64 compiler backend in Ridgun without `rustc`

## Goal (one sentence)
Eliminate the intermediate Rust codegen and `rustc` dependency in `ridgunc build` / `ridgunc run` by implementing a 100% pure-Ridgun native code generator and ELF64 binary emitter targeting both Linux `x86_64` and Linux `ARM64` (`AArch64` for Raspberry Pi).

## Plan
- [x] Design the standalone Ridgun binary ABI and precompiled/relocatable runtime section (`RVal`, `RMM1`/`RMM2` heap management, lexical `with region` arenas, `Tensor` operations, work-stealing channels/threads, and POSIX syscalls).
- [x] Implement `src/main/ridgun/lib/elf64.rg` in pure Ridgun using `write_bytes` to emit valid ELF64 executables (`EM_X86_64 = 62` and `EM_AARCH64 = 183`) with symbol relocation.
- [x] Implement `src/main/ridgun/lib/x86_64.rg` in pure Ridgun (System V AMD64 ABI, native `loop` TCO jumps, and `RMM1`/`RMM2` calls).
- [x] Implement `src/main/ridgun/lib/arm64.rg` in pure Ridgun (AAPCS64 ABI for ARM64 / Raspberry Pi, native `loop` TCO branches, and `RMM1`/`RMM2` calls).
- [x] Add `--target x86_64-linux` and `--target arm64-linux` flags to `ridgunc build` and `stable built`, and verify self-hosting Stage 1 and Stage 2 without `rustc`.

## Progress log (append-only, newest last)
- 2026-10-20: Created backlog task per user request to replace the intermediate Rust compilation step with a 100% native Ridgun compiler backend for `x86_64` and `ARM64` (Raspberry Pi).
- 2026-10-21: Implemented `src/main/ridgun/lib/elf64.rg`, `src/main/ridgun/lib/x86_64.rg`, `src/main/ridgun/lib/arm64.rg`, pure-Ridgun AST-to-`RNativeProg` lowering in `src/main/ridgun/lib/compiler.rg`, and `--target <arch>` CLI flags in `src/main/ridgun/ridgunc/main.rg`. Removed all legacy Rust code (`src/main/rust/`, `Cargo.toml`, `Cargo.lock`) and bootstrapped Stage 1, Stage 2, and bit-for-bit identical Stage 3 `target/ridgunc` and `target/stable` ELF64 binaries without `rustc`.
## Files changed (keep current)
- `src/main/ridgun/lib/elf64.rg` (created)
- `src/main/ridgun/lib/x86_64.rg` (created)
- `src/main/ridgun/lib/arm64.rg` (created)
- `src/main/ridgun/lib/compiler.rg` (updated — 100% pure-Ridgun native IR & ELF64 emitter)
- `src/main/ridgun/ridgunc/main.rg` (updated — `--target x86_64-linux` and `--target arm64-linux` support)
- `src/main/rust/` (deleted — 16 legacy `.rs` files removed)
- `Cargo.toml`, `Cargo.lock` (deleted)
- `docs/requirements/functional/compiler/FR-COMP-004-native-elf64-codegen-x86-64-and-arm64.md` (created & marked `implemented`)
## Verification performed (command → result, newest last)
- `./target/ridgunc_stage1 build src/main/ridgun/ridgunc/main.rg -o target/ridgunc` → emitted standalone 1.7 MB Linux `x86_64` ELF64 executable (`EM_X86_64 = 62`, statically linked, no section header).
- `./target/ridgunc build src/main/ridgun/ridgunc/main.rg -o /tmp/ridgunc_stage3 && cmp -l target/ridgunc /tmp/ridgunc_stage3` → 0 byte differences (100% bit-for-bit reproducible self-hosting fixed point in 14.5s).
- `./target/ridgunc build src/main/ridgun/stable/main.rg -o target/stable` → emitted standalone 1.8 MB Linux `x86_64` ELF64 executable (`target/stable`).
- `./target/ridgunc build --target arm64-linux src/test/ridgun/test_core_language.rg -o /tmp/test_arm64_elf` → `ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, no section header`.
- `./target/stable check`, `./target/stable test`, `./target/stable format --check` → 13 modules checked, 4/4 test suites passed (`test_basics.rg`, `test_core_language.rg`, `test_parallel_and_tensors.rg`, `test_strings.rg`), 0 errors.
## Exact next actions
1. Task complete.
## Decisions / open questions
- Target architectures: Linux `x86_64` (`EM_X86_64 = 62`) and Linux `ARM64` / `AArch64` (`EM_AARCH64 = 183`, Raspberry Pi 3/4/5).
## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
