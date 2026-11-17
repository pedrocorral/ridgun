---
id: ADR-0016
title: No Linux shared object is emitted until a program can call it
status: accepted
date: 2026-11-17
supersedes: []
affects: [FR-COMP-006, src/main/ridgun/ridgunc/main.ridgun, src/main/ridgun/stable/main.ridgun, src/main/ridgun/lib/compiler.ridgun, src/main/ridgun/lib/llvm.ridgun, TASK-0096]
---
# ADR-0016 — No Linux shared object is emitted until a program can call it

## Context
`ridgunc build --lib -o x` and `stable build lib` wrote `x.so` next to the `.ridgunlib`, as FR-COMP-006 AC-2 asks. Checked on 2026-11-17 with `dlopen` in a C program: the file has no dynamic section ("object file has no dynamic section"), exports no library function (only `memcpy`, `memset` and runtime helpers) and has no way to start the runtime. The tests only read the ELF header (`e_type == 3`). No consumer is known.
Ridgun executables are static and have no loader, so a Ridgun program cannot load a `.so`; Ridgun libraries are shared as `.ridgunlib`, which keeps generic types and `expand type`.

## Options considered
1. Make the `.so` real on the IR runtime: exported C-ABI functions, runtime start on first call, a value conversion at the boundary. A new feature of several hours with no requester.
2. Keep the file as it is. It looks like a library and is not, and it keeps the old runtime blob alive.
3. Stop emitting it.

## Decision
Option 3. `ridgunc build --lib` writes the `.ridgunlib` only; `ridgunc build --so` for a Linux target stops with a message that names this ADR; `stable build lib` writes `target/<name>.ridgunlib`. The Mach-O (`.dylib`) and PE (`.dll`) emitters are not touched here. If a program in another language must call Ridgun, it is designed then as a feature of its own (exported functions with the C ABI, the runtime started by a constructor) on the IR runtime.

## Consequences
- FR-COMP-006: statement item 1 and AC-2 and AC-3 lose the `.so`.
- The old runtime blob is no longer needed by any library path; only the pure x86-64 encoder uses it (TASK-0096).
- Dead code left for later removal: `elf64` image kind 3.
