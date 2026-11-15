---
id: ADR-0011
title: WebAssembly is a native backend of ridgunc, and the playground runs ridgunc.wasm in the browser
status: accepted
date: 2026-11-12
supersedes: []
affects: [FR-COMP-015, src/main/ridgun/lib/compiler.ridgun, src/main/ridgun/ridgunc/main.ridgun, src/main/ridgun/lib/wasm.ridgun, src/main/ridgun/lib/wasm32.ridgun, tests/run.ridgun]
---
# ADR-0011 — WebAssembly is a native backend

## Context
We want a page, `ridgun.com/play`, where anyone can write a Ridgun program and run it without installing anything. The server must only serve static files: no cost per visitor, and no strangers' code running on our machines.

Ridgun has no WebAssembly output today. `ridgunc` has three backends: x86-64 and ARM64 write machine code and their runtime themselves; LLVM writes IR but links the x86-64 runtime at fixed addresses, so it cannot target wasm as it is.

## Options considered
1. **Compile on a server** (the Go and Rust playgrounds). Costs a server per visitor and needs a sandbox for unknown code.
2. **An interpreter in JavaScript.** A second implementation of the language that drifts from the real one.
3. **The x86-64 `ridgunc` inside an x86-64 emulator compiled to wasm** (for example Blink). The real compiler, quickly; slow (seconds per build), and depends on what the emulator supports (threads, memory).
4. **wasm through LLVM** (`llc -march=wasm32`, `wasm-ld`). LLVM builds the structured control flow; but the runtime must be rewritten as IR, and `ridgunc` would need LLVM at build time, so it cannot run in the browser.
5. **A native wasm backend, like ARM64.** `ridgunc` writes the `.wasm` module itself, runtime included. Then `ridgunc` compiles itself to `ridgunc.wasm`, which runs in the browser at near-native speed. The most work: about the size of the ARM64 backend.

## Decision
Option 5. WebAssembly is a fourth backend, with the same shape as ARM64:

- **`wasm.ridgun`** translates the NIR to wasm instructions. The runtime comes from the target-neutral LLVM IR runtime compiled by `llc` (amended by ADR-0013); it was first planned here as hand-written wasm functions.
- **`wasm32.ridgun`** writes the binary module (types, imports, functions, memory, exports, code, data), as `elf64.ridgun` writes ELF.
- **`--target wasm32`** selects it, through `emit elf for target` like the other targets.

The design rules:

- **Values stay 64-bit (`i64`).** Addresses are 32-bit (`wasm32`): the backend converts at each load and store. wasm32 runs everywhere; wasm64 is still missing in Safari.
- **Control flow.** wasm has no jump to a label. Each function becomes a `loop` around a `br_table` that selects the next NIR block. It is general and mechanical.
- **Memory.** One linear memory. The allocator grows it with `memory.grow` instead of `mmap`. RMM rules do not change.
- **System.** wasm has no system calls. The module imports a small set of functions (write, read, clock, exit, files, arguments). It is one more PAL implementation (ADR-0008). In the browser, about 200 lines of JavaScript implement them. Outside the browser, the same imports map to WASI.
- **Agents.** First on one thread: an agent's step runs when its message arrives. Later, Web Workers can give each agent its own thread.
- **Network.** `net …` is not available on wasm. The checker reports its use for this target.

The playground then has three parts:

1. The Linux `ridgunc` builds `ridgunc --target wasm32`, which gives `ridgunc.wasm`. It is the same compiler from the same source, as `ridgunc.exe` is for Windows.
2. The page loads `ridgunc.wasm` and compiles the visitor's program to a `.wasm` in memory.
3. The page runs that `.wasm` with the JavaScript imports and shows its output.

Option 3 (emulator) is not taken: with option 5 it is no longer needed.

## Consequences
- New files `src/main/ridgun/lib/wasm.ridgun` and `src/main/ridgun/lib/wasm32.ridgun`. `compiler.ridgun` and `ridgunc/main.ridgun` learn the target. FR-COMP-015 gains the wasm32 target, or a new FR covers it.
- Testing needs a wasm engine on this machine. None is installed (no wasmtime, no Node). wasmtime is a download of about 20 MB and needs the user's approval before the first test.
- `tests/run.ridgun` runs the promised behaviours on the wasm backend too, except network and true parallelism.
- The playground page lives in www-ridgun. It is static: `ridgunc.wasm`, a JavaScript host and the editor.
- Work, in order: TASK-0086 (module writer), TASK-0087 (NIR to wasm), TASK-0088 (the IR runtime of ADR-0013, on wasm32 first), TASK-0089 (PAL imports and hosts), TASK-0090 (`--target wasm32` end to end and `ridgunc.wasm`), TASK-0091 (playground page).
