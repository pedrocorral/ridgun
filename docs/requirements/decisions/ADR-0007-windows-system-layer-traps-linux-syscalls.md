---
id: ADR-0007
title: On Windows, a system layer traps the runtime's Linux system calls and does them with KERNEL32
status: accepted
date: 2026-11-12
supersedes: []
affects:
  - FR-COMP-015
  - src/main/ridgun/lib/pe64.rg
  - docs/etc/runtime_windows.md
---
# ADR-0007 — On Windows, a system layer traps the runtime's Linux system calls

## Context
- The x86_64 runtime is about 85 KiB of machine code at fixed addresses from `0x401000`. Every backend
  copies it as it is. It makes Linux system calls (`syscall`, number in `rax`, arguments in `rdi`, `rsi`,
  `rdx`, `r10`, `r8`, `r9`) at 99 places.
- Some code-generator snippets also make Linux system calls: 21 places in 18 instruction forms (`x86 sort by`,
  `x86 list get`, `x86 tensor bounds`, builtins 1, 32, 33, 50, 57, 86, 87 and 96 to 99).
- A Windows `.exe` built by 1.0.1 imported 7 KERNEL32 functions and ran the Linux code: the first `syscall`
  fails (Solstice report of 2026-11-12).
- The runtime keeps variables in its first page (`0x400158..0x400178`, `0x400F00..0x401000`). In a PE image
  that page holds the headers and is read-only.
- No Windows machine is available to the compiler team; LLVM tools (clang 19, lld) can build Windows code.

## Options considered
1. **Rewrite the runtime for Windows:** a second runtime that calls KERNEL32 directly. The runtime is
   machine code without its source in the repository; a second copy doubles every future runtime change.
2. **Patch each call site to a `call` into a layer:** a `call rel32` needs 5 bytes and a `syscall` has 2;
   the code around each site would have to move.
3. **Trap each call site:** in the Windows image replace each `syscall` (`0F 05`) by `ud2` (`0F 0B`), the same
   length. A vectored exception handler catches the fault, does the call with KERNEL32 and resumes after the
   instruction.

## Decision
Adopt **Option 3**.
- The runtime and the code generator stay the same for every target. Only `pe64.rg` changes the 2-byte
  instructions at known offsets, and a unit test fails when an offset no longer holds a `syscall`.
- The layer is C (`rtw.c`), built once with clang into position-independent bytes kept in `pe64.rg`, as the
  runtime extension (`rtx.c`) is.
- The layer reads the Linux registers from the exception `CONTEXT`, so it follows the Linux ABI exactly:
  the result in `rax`, `rcx` and `r11` set as the kernel sets them, every other register kept.
- `fork` and `execve` are emulated together, as `vfork`: `fork` saves the thread's registers and returns 0;
  the child's `execve` starts the program with `CreateProcessW` and resumes the parent at the `fork` with
  the new process id. The runtime's child path only prepares arguments, so it can run in the parent.
- The PE headers move to offset `0x400` of the first page, between the runtime's two areas of variables,
  and the layer makes the page writable at start.

## Consequences
- Each system call costs a CPU exception (a few microseconds). The runtime makes few calls per operation.
- A debugger attached to the program stops at each `ud2` as a first-chance exception.
- A call the layer does not know returns `-ENOSYS`; sockets are not covered yet.
- A change to the runtime or to a snippet with a `syscall` must update `win rt sites` or `win sys sites`
  (the unit test `test cross platform targets.rg` points it out).
- arm64 Windows images and macOS images are not covered by this decision.
