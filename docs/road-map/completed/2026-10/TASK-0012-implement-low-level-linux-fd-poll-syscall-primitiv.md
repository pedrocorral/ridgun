---
id: TASK-0012
title: Implement cross-platform PAL I/O, polling, process & syscall primitives and declarative with timeout blocks
status: completed
created: 2026-10-21
completed: 2026-10-21
requirements:
  - FR-COMP-007
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-007-low-level-posix-fd-poll-syscalls-and-with-timeout-blocks.md
  - src/main/ridgun/lib/lexer.rg
  - src/main/ridgun/lib/parser.rg
  - src/main/ridgun/lib/typecheck.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
scope:
  - src/main/ridgun/lib/
  - src/test/ridgun/
  - docs/
  - harness/
owner: agent-001
claimed: 2026-10-21T17:56:16Z
claimed_by: agent gemini@solarfall
---
# TASK-0012 — Implement cross-platform PAL I/O, polling, process & syscall primitives and declarative `with timeout` blocks

## Goal (one sentence)
Deliver `FR-COMP-007` by implementing duration literals (`_ms`, `_s`, `_min`), OS-agnostic PAL primitives (`sys open mode`, `sys open`, `sys close`, `sys read fd`, `sys write fd`, `sys poll`, `sys terminate`, `sys kill`, `sys call`, `sys deadline ms`, `sys remaining ms`), and declarative `with timeout <duration> do` blocks across the compiler, native kernels (`x86_64` and `ARM64`), VM, and formatter.

## Plan
- [x] Add duration unit suffixes (`_ms`, `_s`, `_min`) to `src/main/ridgun/lib/lexer.rg`.
- [x] Add cross-platform PAL built-in primitives (`sys_open_mode`, `sys_open`, `sys_close`, `sys_read_fd`, `sys_write_fd`, `sys_poll`, `sys_terminate`, `sys_kill`, `sys_call`, `sys_deadline_ms`, `sys_remaining_ms`) and `with timeout <expr> do <body>` (plus `with region <r>, timeout <t> do <body>`) to `src/main/ridgun/lib/parser.rg`, `src/main/ridgun/lib/typecheck.rg`, and `src/main/ridgun/lib/vm.rg`.
- [x] Implement the native runtime kernel support and lowering in `src/main/ridgun/lib/compiler.rg`, `src/main/ridgun/lib/x86_64.rg`, and `src/main/ridgun/lib/arm64.rg`.
- [x] Increment the version (`+0.0.1` -> `0.9.5`) in `build.rg`, `src/main/ridgun/ridgunc/main.rg`, `src/main/ridgun/stable/main.rg`, `README.md`, and `harness/`.
- [x] Rebuild self-hosted `bin/ridgunc` and `bin/stable`, add automated tests in `src/test/ridgun/test lib and plugins.rg`, and update `harness/`.

## Progress log (append-only, newest last)
- 2026-10-21: Created `FR-COMP-007` and `TASK-0012`.
- 2026-10-21: Updated `FR-COMP-007` and `TASK-0012` with cross-platform PAL-agnostic design (`sys open mode`, normalized PAL flags/events/signals, `sys terminate`).
- 2026-10-21: Implemented `FR-COMP-007` across `lexer.rg`, `parser.rg`, `typecheck.rg`, `compiler.rg`, `x86_64.rg`, `arm64.rg`, and `vm.rg`; added built-in `SysOs` (`Linux | MacOS | Windows`) and `SysArch` (`X86_64 | Arm64`) target ADTs (`sys os => SysOs`, `sys arch => SysArch`); stored official PAL & system library specification in `docs/lang/pal-and-system-libraries.md` (and synced `/tmp/ridgun_posix_io_library_spec.md`); bumped version to `0.9.5`; rebuilt self-hosted `bin/ridgunc` and `bin/stable`; added automated verification in `src/test/ridgun/test lib and plugins.rg`.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-007-low-level-posix-fd-poll-syscalls-and-with-timeout-blocks.md`
- `docs/requirements/functional/compiler/INDEX.md`
- `docs/lang/pal-and-system-libraries.md`
- `docs/lang/INDEX.md`
- `docs/lang/spec.md`
- `src/main/ridgun/lib/lexer.rg`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/typecheck.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/arm64.rg`
- `src/main/ridgun/lib/vm.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test lib and plugins.rg`
- `build.rg`
- `README.md`
- `harness/`

## Verification performed (command → result, newest last)
- `./bin/stable check` → 13 modules checked, 0 errors.
- `./bin/stable test` → 5/5 test suites passed (`test basics.rg`, `test core language.rg`, `test lib and plugins.rg`, `test parallel and tensors.rg`, `test strings.rg`).
- `aix docs validate` → 0 errors.

## Exact next actions
1. Task complete.

## Decisions / open questions
- Cross-platform PAL semantics approved by user so `.rglib` libraries work unmodified across Linux (`x86_64`/`ARM64`), macOS, and Windows.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
