---
id: ADR-0013
title: The whole runtime is written once, in target-neutral LLVM IR, and compiled by llc for each target
status: accepted
date: 2026-11-15
supersedes: []
affects: [ADR-0011, ADR-0008, FR-COMP-026, FR-COMP-022, FR-COMP-023, TASK-0088, src/main/ridgun/lib/x86_64.ridgun, src/main/ridgun/lib/arm64.ridgun, src/main/ridgun/lib/llvm.ridgun, src/main/ridgun/lib/pe64.ridgun, src/main/ridgun/lib/wasm.ridgun, docs/etc/runtime_ext.md]
---
# ADR-0013 — The whole runtime is target-neutral LLVM IR

## Context
The runtime is in pieces, each with its own source and its own copy of the semantics:

- the base runtime: machine code bytes in `x86_64.ridgun`, placed at `0x401000`; the LLVM backend links the same bytes with a linker script;
- the extension `rtx.c` and the Windows layer: freestanding C, compiled by clang to bytes pasted into `x86_64.ridgun` and `pe64.ridgun` (`docs/etc/runtime_ext.md`);
- about 20 helpers written as LLVM IR in `llvm.ridgun` (fast paths, used only by the LLVM backend);
- the ARM64 runtime in `arm64.ridgun`, mostly stubs;
- the scalar runtime in `wasm.ridgun` (TASK-0087).

ADR-0011 adds one more piece: the runtime as wasm functions. Each new target repeats the work and the semantics drift.

## Decision
The principle: **one source of the runtime for every target.** The source is LLVM IR, compiled by `llc` for each target (x86-64, ARM64, wasm32, and the PE and Mach-O variants).

Rules:

1. **Target-neutral IR.** Values are `i64` words. Pointers are converted explicitly (`inttoptr`/`ptrtoint`), so the same IR works with 32-bit addresses (wasm32). No inline assembly in the runtime logic.
2. **The system is the PAL (ADR-0008).** The IR calls PAL functions for every system operation. Each target implements them: Linux system calls (inline assembly in the PAL only), the Windows layer, and imports on wasm. Threads use atomics plus a small `clone` in the Linux PAL. Variables now kept in page 0 become IR globals.
3. **Hot and cold parts.** The hot functions (clone, drop, integer operations, list and tensor access) stay as IR that the LLVM backend can inline into the program. The cold part is compiled once per target and kept, as the `.rt` cache is today.
4. **The pure backends embed `llc` output.** The x86-64 and ARM64 encoders and the wasm module writer include the runtime compiled by `llc` for their target. On x86-64 it is position-independent code at a fixed address, the same path `rtx.c` already follows (PC-relative relocations only, bytes pasted into the source). On wasm32 the runtime functions go into the module beside the program's functions.

LLVM is not another language: it is the intermediate form that Rust, Swift and Zig also generate. Regenerating the runtime needs `llc`; compiling a program with a pure backend does not.

## Consequences
- **Functionality:** nothing is lost. wasm still has no threads and no network (ADR-0011), whatever the source.
- **Performance:** nothing is lost. The LLVM backend can inline the hot runtime; the pure backends get `llc -O2` code.
- **Cost:** the rewrite. The semantics of the x86-64 base runtime and of `rtx.c` move to IR; the 310 promised behaviours must pass on every backend.
- **ADR-0011:** the runtime is no longer hand-written as wasm instructions in `wasm.ridgun`; it comes from this IR. The rest of ADR-0011 stands (NIR to wasm, module writer, PAL as imports, `ridgunc.wasm`).
- **`wasm.ridgun`:** its scalar runtime (TASK-0087) is provisional; it is replaced by the IR runtime.
- **TASK-0088** becomes: write the target-neutral IR runtime and use it on wasm32 first. Later tasks move x86-64, ARM64 and Windows onto it and delete the byte blobs, the C sources and the duplicated fast paths.
- **Docs to update:** FR-COMP-026 (runtime source), `docs/etc/runtime_ext.md` when the extension moves.
