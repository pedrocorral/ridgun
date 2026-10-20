---
id: TASK-0006
title: Implement 100% standalone native x86_64 and ARM64 (Raspberry Pi) ELF64 compiler backend in Ridgun without rustc
status: pending             # pending | going-on | blocked | completed
created: 2026-10-20
completed:
after: [TASK-0004]
requirements: [FR-COMP-002, FR-COMP-003]
tests: []
security: []
context_files: [src/main/ridgun/lib/compiler.rg, src/main/ridgun/ridgunc/main.rg, docs/etc/cmm_architecture.md]
scope: [src/main/ridgun/lib/x86_64.rg, src/main/ridgun/lib/arm64.rg, src/main/ridgun/lib/elf64.rg]
owner:
claimed:
claimed_by:
policy:
---
# TASK-0006 — Implement 100% standalone native `x86_64` and `ARM64` (`AArch64` / Raspberry Pi) ELF64 compiler backend in Ridgun without `rustc`

## Goal (one sentence)
Eliminate the intermediate Rust codegen and `rustc` dependency in `ridgunc build` / `ridgunc run` by implementing a 100% pure-Ridgun native code generator and ELF64 binary emitter targeting both Linux `x86_64` and Linux `ARM64` (`AArch64` for Raspberry Pi).

## Plan
- [ ] Design the standalone Ridgun binary ABI and precompiled/relocatable runtime section (`RVal`, `RMM1`/`RMM2` heap management, lexical `with region` arenas, `Tensor` operations, work-stealing channels/threads, and POSIX syscalls).
- [ ] Implement `src/main/ridgun/lib/elf64.rg` in pure Ridgun using `write_bytes` to emit valid ELF64 executables (`EM_X86_64 = 62` and `EM_AARCH64 = 183`) with symbol relocation.
- [ ] Implement `src/main/ridgun/lib/x86_64.rg` in pure Ridgun (System V AMD64 ABI, native `loop` TCO jumps, and `RMM1`/`RMM2` calls).
- [ ] Implement `src/main/ridgun/lib/arm64.rg` in pure Ridgun (AAPCS64 ABI for ARM64 / Raspberry Pi, native `loop` TCO branches, and `RMM1`/`RMM2` calls).
- [ ] Add `--target x86_64-linux` and `--target arm64-linux` flags to `ridgunc build` and `stable built`, and verify self-hosting Stage 1 and Stage 2 without `rustc`.

## Progress log (append-only, newest last)
- 2026-10-20: Created backlog task per user request to replace the intermediate Rust compilation step with a 100% native Ridgun compiler backend for `x86_64` and `ARM64` (Raspberry Pi).
## Files changed (keep current)
-
## Verification performed (command → result, newest last)
-
## Exact next actions
1. Write requirement `FR-COMP-004` specifying the standalone `x86_64` and `ARM64` ELF64 code generation backend before starting `TASK-0006`.
## Decisions / open questions
- Target architectures: Linux `x86_64` (`EM_X86_64`) and Linux `ARM64` / `AArch64` (`EM_AARCH64`, Raspberry Pi 3/4/5).
## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
