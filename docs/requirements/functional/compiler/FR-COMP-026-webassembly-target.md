---
id: FR-COMP-026
title: WebAssembly Target (wasm32)
type: functional
domain: compiler
status: approved
priority: should
created: 2026-11-14
updated: 2026-11-14
depends_on: [FR-COMP-004, FR-COMP-015]
related: [ADR-0008, ADR-0011]
verified_by: [src/test/ridgun/test wasm.ridgun, src/test/ridgun/test wasm backend.ridgun]
---
# FR-COMP-026 — WebAssembly Target (`wasm32`)

## Statement
`ridgunc build --target wasm32 <entry.ridgun> -o <out.wasm>` SHALL write a WebAssembly module that runs the
program, with no external tool. The module is written by `ridgunc` itself, runtime included, as for the other
native targets (ADR-0011).

## Terms
- **Module writer:** `src/main/ridgun/lib/wasm32.ridgun`. It encodes a module description into the binary format
  of WebAssembly 1.0 (magic `\0asm`, version 1).
- **Backend:** `src/main/ridgun/lib/wasm.ridgun`. It translates the NIR and the runtime into that description.
- **Host:** the code that runs the module and implements its imports: a WASI engine, or JavaScript in a browser.
- **Frame:** the slots of one NIR function call, 8 bytes each, on a shadow stack in linear memory.

## Requirements
1. **Module writer.** It SHALL encode, from a module description, the sections type (1), import (2), function (3),
   memory (5), global (6), export (7), code (10) and data (11), in that order, leaving out empty sections.
   Integers SHALL use LEB128 (unsigned for counts, sizes and indexes; signed for `i32.const` and `i64.const`).
   A function's locals SHALL be grouped into runs of the same type.
2. **Values and addresses.** Ridgun values SHALL be `i64`. Memory addresses SHALL be `i32` (one linear memory).
3. **Control flow.** Every NIR function SHALL become one wasm function. Jumps to NIR labels SHALL go through a
   `loop` and a `br_table` over the function's blocks. A NIR function takes the address of its arguments (`i32`)
   and returns the value (`i64`). Its frame comes from a shadow stack that starts after the rodata and grows down;
   a call that would pass the stack's bottom SHALL stop the program (`unreachable`).
4. **Runtime.** The runtime SHALL be wasm functions in the same module, one per runtime slot of the native targets,
   with the same arguments and result; the result of every runtime call is the new accumulator, as on x86-64. The allocator SHALL grow the memory with
   `memory.grow`. RMM rules SHALL not change.
5. **System.** The module SHALL import its system operations from the module `ridgun` (write, read, clock, exit,
   files, arguments, environment). It is one more PAL implementation (ADR-0008). A WASI host and a browser host
   SHALL implement them.
6. **Agents.** Agents SHALL run on one thread: an agent's step runs when its message arrives.
7. **Not available.** `net …` SHALL be rejected by the checker for `wasm32`, naming the builtin and the target.
8. **Self-build.** `ridgunc` SHALL compile itself with `--target wasm32`. The resulting `ridgunc.wasm`, run by a
   host, SHALL compile a program to the same module bytes as the Linux `ridgunc`.

## Acceptance criteria
- **AC1.** The module writer encodes a module with one function `() -> i64` that returns 42, exported as
  `answer`, to the exact expected bytes. Unsigned and signed LEB128 encode known values to known bytes.
- **AC2.** The module writer encodes imports, a memory, a global, exports and a data segment to the exact
  expected bytes, and runs of locals are grouped.
- **AC3.** A program with arithmetic, guards and recursion, built with `--target wasm32`, runs under a WASI host
  and prints the same output as on Linux.
- **AC4.** The promised behaviours of `tests/run.ridgun` pass on `wasm32`, except network and true parallelism.
- **AC5.** A program that uses `net …` is rejected for `wasm32` with the builtin and the target named.
- **AC6.** `ridgunc.wasm` builds a program to the same bytes as the Linux `ridgunc` with `--target wasm32`.
- **AC7.** The module exports `ridgun_main`, which runs `main` and returns its value. A program with Int arithmetic,
  guards, recursion, a self tail call of 100 000 rounds, Bool patterns and signed division, built with
  `--target wasm32`, validates, and `ridgun_main` returns the value the Linux build computes.
