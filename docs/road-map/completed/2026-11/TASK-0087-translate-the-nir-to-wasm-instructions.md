---
id: TASK-0087
title: Translate the NIR to wasm instructions
status: completed
created: 2026-11-12
completed: 2026-11-14
requirements: [FR-COMP-026]
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [docs/requirements/decisions/ADR-0011-webassembly-is-a-native-backend.md]
scope: [src/main/ridgun/lib/wasm.ridgun, src/main/ridgun/lib/wasm32.ridgun, src/main/ridgun/lib/compiler.ridgun, src/main/ridgun/lib/parser.ridgun]
owner: agent-001
claimed: 2026-11-14T17:31:47Z
claimed_by: claude claude@solarfall
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0087 — NIR to wasm instructions

## Goal (one sentence)
`src/main/ridgun/lib/wasm.ridgun` translates each NIR function to wasm code.

## Plan
- [x] Values are `i64`; addresses are `i32` (wrap at each load and store).
- [x] Each function is a `loop` with a `br_table` that selects the next NIR block (labels become block indexes).
- [x] Calls to runtime slots become `call` to runtime function indexes.
- [x] `emit elf for target` in `compiler.ridgun` gains `"wasm32"`.

## Progress log (append-only, newest last)
- 2026-11-12: Created with ADR-0011. Needs TASK-0086.

- 2026-11-14: `wasm.ridgun` written. Each NIR function is a wasm function `(i32 args) -> i64` with locals frame, accumulator and next block; its frame (8 bytes per slot) comes from a shadow stack after the rodata that grows down, and passing its bottom stops the program. Blocks are split at labels; a `loop` holds nested blocks and a `br_table` on the next block. Every NIR instruction is translated: runtime calls go to 67 runtime functions (the 56 native slots, 56..63 for what x86-64 encodes inline, 64..66 for the heap entry points), each `(i64 x n) -> i64`, and their result is the accumulator as on x86-64. The scalar runtime is written: init frame, epilogue, tail call copy, clear locals, clone, drop, move, store, rebind, drop slot, as bool, match int, match bool, not, and the binary operator on tagged Ints and Bools. The heap, PAL and agent slots stop (`unreachable`) until TASK-0088 and TASK-0089. Exports: `memory`, `ridgun_main` (runs main, returns its value) and `_start`. `--target wasm32` (and `wasm`) selects it.
- 2026-11-14: Patch: `is core compiler mod` in `parser.ridgun` lists the compiler's modules by name; `wasm32` and `wasm` had to be added, or a program that imports `elf64` before `wasm` cannot see the NIR types inside `wasm`. Bootstrap: stage 1 built without the wasm hook, then the full sources. General fix still to do: the list should come from the compiler's lib folder, not from names.
- 2026-11-14: Open: `sys os` and `sys arch` give `Linux` and `X86_64` on wasm32; the language has no constructors for a wasm host yet.

## Verification performed (command → result, newest last)
- `ridgunc check src/main/ridgun/lib/wasm.ridgun` → 0 errors.
- Bootstrap s1 → s2 → s3: s2 and s3 differ only in the stamp (4 bytes, a temporary file name).
- `test wasm backend.ridgun` (AC7): fib 20, a 100 000-round tail call, collatz 27, Bool patterns and signed `%`; `wasm-validate` ok; `wasm-interp -r ridgun_main` → `i64:13530000321997` (tagged 6765000160998, the Linux value).
- With s3: suite 310/310 (llvm 162, x86 148); 10 unit test files, 0 fails; libs 35/35.
- 1.0.11 (s4 → s5): s4 and s5 differ only in the stamp; suite 310/310; `test wasm` and `test wasm backend` 0 fails. Installed in `bin/`.
- `ridgunc build --target wasm32 src/main/ridgun/ridgunc/main.ridgun` → 5.9 MB module in 2 min 45 s; `wasm-validate` ok (every NIR instruction the compiler uses gives valid code).

## Exact next actions
1. TASK-0088: the heap runtime (allocator with `memory.grow`, clone and drop, strings, lists, ADTs) in slots 64..66 and the rest.
