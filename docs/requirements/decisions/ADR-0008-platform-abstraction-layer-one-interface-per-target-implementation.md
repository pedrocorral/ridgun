---
id: ADR-0008
title: The PAL is one interface of Ridgun operations, implemented once per target and chosen at compile time
status: accepted
date: 2026-11-12
supersedes: []
affects:
  - FR-COMP-007
  - FR-COMP-015
  - FR-COMP-022
  - FR-VM-002
  - ADR-0007
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/pe64.rg
  - src/main/ridgun/lib/macho64.rg
  - docs/etc/runtime_ext.md
  - docs/etc/runtime_windows.md
  - tests/run.rg
---
# ADR-0008 — The PAL is one interface of Ridgun operations, implemented once per target

## Context
- FR-COMP-007 defines the `sys …` builtins as a platform abstraction layer (PAL). They are implemented only with Linux system calls.
- Windows images translate those calls back. Each `syscall` becomes `ud2`, and a handler does the call with KERNEL32 (ADR-0007). It costs a CPU exception per call, and it rebuilds Linux structures (`linux_dirent64`, `struct stat`) that the runtime then parses.
- Some Linux ideas have no equivalent elsewhere: `fork`, `clone`, `futex`, the `O_*` and `MAP_*` numbers, `getdents64`. macOS needs the same translation again, through libSystem. The Darwin system call numbers are not a stable interface.
- Libraries reach the system through `sys call` with Linux numbers. libs uses 38 of them, in `posix.rg`, `socket.rg`, `uuid.rg` and `argon2id.rg`: sockets, files, processes, signals, time and random bytes.
- A builtin takes precedence over a user function of the same name. In 1.0.3, the new `sys unlink`, `sys rmdir` and `sys rename` hid the functions of the same names in libs `posix.rg`, and had to be renamed.
- The base runtime is machine code without source. The runtime extension (`rtx.c`, ids ≥ 100) has source and is shared by LLVM and x86-64.

## Options considered
1. **Keep Linux as the interface and translate per OS** (today). One implementation, but every other OS pays a trap per call, and some semantics cannot be emulated.
2. **Dispatch at run time** through a table of OS functions. One binary could run on several systems, but every call pays an indirection that no build needs: the target is known when compiling.
3. **One interface of Ridgun operations, one implementation per target, chosen at compile time.** Like LLVM IR for machines: the program and libraries see the operations, and each backend lowers them to its own system.

## Decision
Adopt **Option 3**.

1. **Interface.** The PAL is the set of builtins that touch the system. Each operation states its meaning in Ridgun terms, not as a system call:
   - **Files and folders:** `sys open`, `sys read fd`, `sys write fd`, `sys close`, `file lstat` (returns a record), `list dir`, `sys mkdir`, `remove file`, `remove dir`, `rename path`, `sys chdir`, `sys getcwd`.
   - **Processes:** `sys exec` (program, arguments, environment), `sys pipe`, `sys waitpid`, `sys kill`, `sys terminate`. There is no `fork` operation.
   - **Sockets** (new family): TCP connect, listen and accept; send, receive and shutdown; socket options that every system has; waiting on several handles.
   - **Time and random bytes:** clocks, sleep, `getrandom`-style bytes.
   - **Threads and waits:** what agents and `||` need (start a thread, wait on an address, wake), internal to the runtime.

   An operation is defined by its intent, so each target can use its best primitive (for example, IOCP or `epoll` behind a wait on several sockets).
2. **Values.**
   - Handles are non-negative `Int`s. A target keeps its own table when its handles are not small integers, as the Windows layer already does.
   - Errors are negative Linux errno numbers (`-2` not found, `-17` exists, `-39` not empty…), on every target, because libraries already compare against them. Each implementation maps its own errors to them.
   - Paths are UTF-8 and accept `/` on every target.
3. **Implementation.**
   - The PAL lives in the runtime extension: one C source (`rtx.c`) with one system part per target (Linux system calls, KERNEL32, libSystem). The compiler copies the bytes built for the target of the image, so a call is a direct call into that code: no trap and no run-time dispatch.
   - Linux keeps its current code.
   - Builtins that live in the base runtime move into the extension one family at a time. For those not moved yet, the Windows trap layer of ADR-0007 stays as the bridge, and shrinks as they move.
4. **`sys call`.** It stays as the escape hatch with Linux numbers, like inline assembly in LLVM. Code that uses it is Linux code. On other targets the trap layer keeps emulating the calls it knows, so existing libraries keep running while they move to PAL operations.
5. **Names.** A user definition shadows a builtin of the same name, as it already shadows the prelude (ADR-0004). Adding a PAL operation never breaks a library that already uses the name.
6. **Order.** Sockets come first, written directly as PAL operations, because `omni.exe` needs HTTP on Windows and a Linux socket emulation over Winsock would be one more translation. Then the file and process families move out of the base runtime. macOS is written on the PAL from the start.

## Consequences
- **Run-time cost.**
  - **Linux:** the same as today.
  - **Windows:** a direct KERNEL32 call per operation instead of a CPU exception, for each operation that has moved.
  - **macOS:** no trap for PAL operations.
  - Code that still uses `sys call` on Windows keeps the trap cost.
- **Engineering cost:** one system part per target for each operation; the base runtime keeps its trap bridge until it has no system calls left.
- **Requirements to update:**
  - FR-COMP-007: the PAL definition, error and handle rules, the socket family, and shadowing.
  - FR-VM-002: its file builtins become PAL operations.
  - FR-COMP-015 and FR-COMP-022: per-target extension bytes, and the extension on ARM64.
  - A new FR for the socket family.
- **Tests to update:**
  - one suite case per PAL operation;
  - `tests/run.rg` gains an `x86_64-windows` backend that runs each case under Wine when the test box answers;
  - a case where a user function named like a builtin wins.
- **Code to update:**
  - `parser.rg`, `typecheck.rg` and `compiler.rg` (shadowing: a builtin is used only when no definition of that name is in scope);
  - `rtx.c` split into a common part and one system part per target, and the build bytes per target in `x86_64.rg`, `pe64.rg` and `macho64.rg`;
  - the Windows trap sites list shrinks as builtins move;
  - `docs/etc/runtime_ext.md` and `docs/etc/runtime_windows.md`.
- **For library teams:** libs `posix.rg` and `socket.rg` can replace `sys call` numbers with PAL operations as they appear; nothing breaks if they do not.
