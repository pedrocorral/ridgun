---
id: FR-COMP-007
title: Cross-platform PAL I/O, polling, process & syscall primitives and declarative `with timeout` blocks
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-10-21
updated: 2026-10-21
depends_on:
  - FR-COMP-004
  - FR-COMP-006
---
# FR-COMP-007 — Cross-platform PAL I/O, polling, process & syscall primitives and declarative `with timeout` blocks

## Statement
The Ridgun compiler (`ridgunc`), its native runtime kernels (`x86_64.rg` and `arm64.rg`, and future macOS `Mach-O` / Windows `PE64` backends), and the stack VM (`vm.rg`) MUST provide an **OS-agnostic Platform Abstraction Layer (PAL)** alongside declarative timeout quotas:
1. **Layer 1 (Cross-Platform PAL Primitives & Target Platform ADTs for `.rglib` System Libraries)**:
   - Pre-declared target platform Sum ADTs:
     - `type SysOs = Linux | MacOS | Windows` (`sys os => SysOs`, open to extension via `expand type SysOs = ...`).
     - `type SysArch = X86_64 | Arm64` (`sys arch => SysArch`, open to extension via `expand type SysArch = ...`).
   - `sys open mode String String => Int` (`path`, `mode_str` in `{"r", "w", "a", "rw", "w+", "a+"}` -> portable handle/descriptor `>= 0` or negative error code, translated by each OS backend).
   - `sys open String Int Int => Int` (`path`, Ridgun PAL normalized `flags` (`0` = read-only, `1` = write-only, `2` = read-write, `64` = create, `512` = truncate, `1024` = append, `2048` = non-blocking), `mode` -> descriptor/handle `>= 0` or `-errno`, translated per OS target).
   - `sys close Int => Int` (`fd` -> `0` or `-errno` / `CloseHandle` status).
   - `sys read fd Int Int => String` (`fd`, `max_bytes` -> string read from `fd`/handle, or `""` on EOF/error).
   - `sys write fd Int String => Int` (`fd`, `data` -> bytes written or `-errno`).
   - `sys poll Int Int Int => Int` (`fd`, Ridgun PAL normalized `events` (`1` = readable/`POLLIN`, `4` = writable/`POLLOUT`, `8` = error/`POLLERR`, `16` = hangup/`POLLHUP`), `timeout_ms` -> `> 0` ready event mask, `0` on timeout, `< 0` on error; when `timeout_ms < 0` inside an active `with timeout` block, automatically uses `sys remaining ms`).
   - `sys terminate Int Bool => Int` (`pid`, `force` -> cross-platform graceful/forced process termination: `SIGTERM`/`SIGKILL` on POSIX, `TerminateProcess` on Windows) and `sys kill Int Int => Int` (`pid`, normalized signal `0`/`2`/`9`/`15` -> `0` or `-errno`).
   - `sys call Int Int Int Int Int Int Int => Int` (`nr`, `a1..a6` -> low-level target-OS ABI syscall escape hatch for platform-specific drivers).
2. **Layer 2 (Declarative `with timeout <duration> do` Execution Quota)**:
   - Duration literals in the lexer (`_ms`, `_s`, `_min`, e.g. `500_ms` -> `500`, `5_s` -> `5000`, `2_min` -> `120000`).
   - `with timeout <ms_expr> do <body>` (and combined `with region <bytes>, timeout <ms> do <body>`) syntax in the parser, formatter, typechecker, analyzer, and compiler.
   - Runtime deadline tracking (`sys deadline ms => Int` and `sys remaining ms => Int`) so code and blocking PAL primitives inside a `with timeout` block automatically see and respect the active deadline across all target operating systems.

## Rationale
Exposing only raw Linux syscall numbers or Linux-specific `O_*` bitflags would break portability across `x86_64` vs `ARM64` Linux (`openat` is `257` on `x86_64` vs `56` on `ARM64`; `poll` is `7` vs `ppoll` `73`) and across macOS (`Mach-O`, where `O_CREAT` is `0x0200` instead of `0x40`) and Windows (`PE64`, which uses `HANDLE`s, `CreateFileW`, and `WaitForSingleObject`/`WSAPoll`). By defining normalized PAL semantics in Layer 1 and declarative `with timeout ... do` quotas in Layer 2, `.rglib` libraries (`posix.rglib`, `io.rglib`, `unix-tools`) remain 100% source-compatible across Linux (`x86_64`/`ARM64`), macOS, and Windows.

## Acceptance criteria
- **AC-1 (Duration Literals)**: `lexer.rg` recognizes `<N>_ms` (`N`), `<N>_s` (`N * 1000`), and `<N>_min` (`N * 60000`) as integer millisecond literals.
- **AC-2 (Cross-Platform PAL Primitives & Target Platform ADTs)**: Built-in `SysOs` (`Linux | MacOS | Windows`) and `SysArch` (`X86_64 | Arm64`), `sys os`, `sys arch`, `sys open mode`, `sys open`, `sys close`, `sys read fd`, `sys write fd`, `sys poll`, `sys terminate`, `sys kill`, `sys call`, `sys deadline ms`, and `sys remaining ms` are supported in `parser.rg`, `typecheck.rg`, `compiler.rg`, `x86_64.rg`, `arm64.rg`, and `vm.rg` (both space-separated and `_`-separated).
- **AC-3 (`with timeout` Block)**: `with timeout <expr> do <body>` (and `with region <bytes>, timeout <ms> do <body>`) sets the active deadline for the lexical scope, clamps to any stricter outer deadline, restores the outer deadline upon exit, and integrates with `sys remaining ms` and `sys poll`.
- **AC-4 (Tests & Documentation)**: Automated tests verify `sys os` / `sys arch`, duration literals, `sys open mode` / `sys open` / `sys write fd` / `sys read fd` / `sys close`, `sys poll` (ready and timeout `0`), `sys terminate` / `sys kill`, `sys call`, and `with timeout ... do` (`sys remaining ms`), and `docs/lang/pal-and-system-libraries.md` + `harness/` are updated.

## Traceability
- Implemented by: `src/main/ridgun/lib/lexer.rg`, `src/main/ridgun/lib/parser.rg`, `src/main/ridgun/lib/typecheck.rg`, `src/main/ridgun/lib/compiler.rg`, `src/main/ridgun/lib/x86_64.rg`, `src/main/ridgun/lib/arm64.rg`, `src/main/ridgun/lib/formatter.rg`, `src/main/ridgun/lib/vm.rg`
- Tested by: `src/test/ridgun/test lib and plugins.rg`
