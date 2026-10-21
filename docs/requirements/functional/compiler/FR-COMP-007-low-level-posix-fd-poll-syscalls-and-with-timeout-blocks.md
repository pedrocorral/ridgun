---
id: FR-COMP-007
title: Low-level Linux FD/poll/syscall primitives and declarative `with timeout` blocks
type: functional
domain: compiler
status: approved
priority: must
created: 2026-10-21
updated: 2026-10-21
depends_on:
  - FR-COMP-004
  - FR-COMP-006
---
# FR-COMP-007 — Low-level Linux FD/poll/syscall primitives and declarative `with timeout` blocks

## Statement
The Ridgun compiler (`ridgunc`) and its native Linux ELF64 runtime kernels (`x86_64.rg` and `arm64.rg`) as well as the stack VM (`vm.rg`) MUST provide:
1. **Layer 1 (Minimal Low-Level Kernel Primitives for `.rglib` System Libraries)**:
   - `sys open String Int Int => Int` (`path`, `flags`, `mode` -> file descriptor `>= 0` or `-errno`)
   - `sys close Int => Int` (`fd` -> `0` or `-errno`)
   - `sys read fd Int Int => String` (`fd`, `max_bytes` -> string read from `fd`, or `""` on EOF/error)
   - `sys write fd Int String => Int` (`fd`, `data` -> bytes written or `-errno`)
   - `sys poll Int Int Int => Int` (`fd`, `events`, `timeout_ms` -> `> 0` revents when ready, `0` on timeout, `< 0` on `-errno`)
   - `sys kill Int Int => Int` (`pid`, `sig` -> `0` or `-errno`)
   - `sys call Int Int Int Int Int Int Int => Int` (`nr`, `a1`, `a2`, `a3`, `a4`, `a5`, `a6` -> raw Linux syscall bridge)
2. **Layer 2 (Declarative `with timeout <duration> do` Execution Quota)**:
   - Duration literals in the lexer (`_ms`, `_s`, `_min`, e.g. `500_ms` -> `500`, `5_s` -> `5000`, `2_min` -> `120000`).
   - `with timeout <ms_expr> do <body>` (and combined `with region <bytes>, timeout <ms> do <body>`) syntax in the parser, formatter, typechecker, analyzer, and compiler.
   - Runtime deadline tracking (`sys deadline ms => Int` and `sys remaining ms => Int`) so code and blocking primitives inside a `with timeout` block automatically see and respect the active deadline.

## Rationale
`posix.rglib`, `io.rglib`, and `unix-tools` require non-blocking/timeout-aware descriptor I/O, process signaling, and raw Linux syscall access without bloating the compiler with dozens of high-level timeout wrappers. Combining Layer 1 (minimal kernel primitives) with Layer 2 (declarative `with timeout ... do` quotas, analogous to `with region ... do`) keeps the compiler small while giving both library authors and application developers clean, idiomatic timeout control.

## Acceptance criteria
- **AC-1 (Duration Literals)**: `lexer.rg` recognizes `<N>_ms` (`N`), `<N>_s` (`N * 1000`), and `<N>_min` (`N * 60000`) as integer millisecond literals.
- **AC-2 (Low-Level Kernel Primitives)**: `sys open`, `sys close`, `sys read fd`, `sys write fd`, `sys poll`, `sys kill`, `sys call`, `sys deadline ms`, and `sys remaining ms` are supported in `parser.rg`, `typecheck.rg`, `compiler.rg`, `x86_64.rg`, `arm64.rg`, and `vm.rg` (both space-separated and `_`-separated).
- **AC-3 (`with timeout` Block)**: `with timeout <expr> do <body>` (and `with region <bytes>, timeout <ms> do <body>`) sets the active deadline for the lexical scope, restores the outer deadline upon exit, and integrates with `sys remaining ms` and `sys poll`.
- **AC-4 (Tests & Documentation)**: Automated tests verify duration literals, `sys open` / `sys write fd` / `sys read fd` / `sys close`, `sys poll` (ready and timeout `0`), `sys call`, and `with timeout ... do` (`sys remaining ms`), and `harness/` is updated.

## Traceability
- Implemented by: `src/main/ridgun/lib/lexer.rg`, `src/main/ridgun/lib/parser.rg`, `src/main/ridgun/lib/typecheck.rg`, `src/main/ridgun/lib/compiler.rg`, `src/main/ridgun/lib/x86_64.rg`, `src/main/ridgun/lib/arm64.rg`, `src/main/ridgun/lib/formatter.rg`, `src/main/ridgun/lib/vm.rg`
- Tested by: `src/test/ridgun/test lib and plugins.rg`
