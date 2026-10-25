---
id: ADR-0002
title: Migrate x86_64 Native Codegen Backend to Pure LLVM IR (llc + ld)
status: accepted
date: 2026-10-25
supersedes: []
affects:
  - FR-COMP-004
  - FR-COMP-010
  - FR-COMP-011
  - src/main/ridgun/lib/llvm.rg
  - src/main/ridgun/lib/compiler.rg
---
# ADR-0002 — Migrate `x86_64` Native Codegen Backend to Pure LLVM IR (`llc` + `ld`)

## Context
Historically, `src/main/ridgun/lib/x86_64.rg` encoded `RNativeInstr` functions and fast-path runtime helpers (`Tensor` indexing/mutation, `sha256_raw` / `sha256_concat` midstate caching, `sys_pipe`, `sys_waitpid`) directly as raw numeric `x86_64` machine-code byte arrays (`[72, 139, ...]`) with manual `rel32`/`rel8` branch-offset arithmetic and manual register/stack allocation. Manual byte-array encoding proved error-prone when adding complex control-flow graphs and SIMD/crypto fast paths, and lacked static verification of register types, SSA dominance, or stack-frame alignment.

## Options considered
1. **Continue maintaining raw numeric `x86_64` byte arrays in `x86_64.rg`**: zero external assembler/linker invocations, but fragile manual branch offset math, no static IR verification, and high maintenance cost for optimization passes (`OPT-004`..`OPT-006`).
2. **Emit pure LLVM IR (`.ll`) in `src/main/ridgun/lib/llvm.rg` and compile/link via `llc -O2 -filetype=obj` + `ld`**: 100% pure LLVM IR text (`.ll`) with zero C source code and zero `clang`/`gcc`/`rustc` invocations; `llc` validates SSA types and CFG dominance and performs register allocation, instruction selection, and `-O2` loop/peephole optimization in ~35 ms; `ld` links the object file against the Ridgun runtime kernel (`0x401000`) and page-0 dispatch table (`0x400080`) in ~4 ms.

## Decision
Adopt **Option 2**. Add `src/main/ridgun/lib/llvm.rg` as the `x86_64` native code generation backend in `ridgunc`:
- Emit pure LLVM IR (`.ll`) for all `RNativeFn` functions, `@__rg_rodata`, `@__rg_page0`, and pure LLVM IR fast-path helpers (`@__rg_sha256_transform`, `@__rg_sha256_compute2` with thread-safe `.bss` spinlocked 2-entry 64-byte midstate cache, `@__rg_tensor_index_1d`, `@__rg_tensor_index_2d`, `@__rg_tensor_index_set_1d`, `@__rg_tensor_index_set_2d`, `@__rg_builtin_tensor_fill`, `@__rg_builtin_tensor_bitop`, `@__rg_builtin_sha256_raw`, `@__rg_builtin_sha256_concat`, `@__rg_builtin_sys_pipe`, `@__rg_builtin_sys_waitpid`).
- Compile `.ll` to `.o` using `/usr/bin/llc -O2 -filetype=obj` and link standalone ELF64 executables/shared libraries using `/usr/bin/ld` with a deterministic linker script placing `.rg_page0` at `0x400080` and `.rg_rt` at `0x401000`.
- Unit-test the LLVM IR codegen and `llc` validation directly in `src/test/ridgun/test llvm codegen.rg`.

## Consequences
- Requirements to update: `FR-COMP-004`, `FR-COMP-011`, `docs/requirements/decisions/INDEX.md`
- Tests to update: add `src/test/ridgun/test llvm codegen.rg`
- Code to update: `src/main/ridgun/lib/llvm.rg`, `src/main/ridgun/lib/compiler.rg`, `src/main/ridgun/ridgunc/main.rg`
