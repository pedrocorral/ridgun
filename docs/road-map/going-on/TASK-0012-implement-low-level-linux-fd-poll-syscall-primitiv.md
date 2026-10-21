---
id: TASK-0012
title: Implement low-level Linux FD/poll/syscall primitives and declarative with timeout blocks
status: going-on
created: 2026-10-21
completed:
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
policy:
---
# TASK-0012 — Implement low-level Linux FD/poll/syscall primitives and declarative `with timeout` blocks

## Goal (one sentence)
Deliver `FR-COMP-007` by implementing duration literals (`_ms`, `_s`, `_min`), low-level Linux kernel primitives (`sys open`, `sys close`, `sys read fd`, `sys write fd`, `sys poll`, `sys kill`, `sys call`, `sys deadline ms`, `sys remaining ms`), and declarative `with timeout <duration> do` blocks across the compiler, native ELF64 kernels (`x86_64` and `ARM64`), VM, and formatter.

## Plan
- [ ] Add duration unit suffixes (`_ms`, `_s`, `_min`) to `src/main/ridgun/lib/lexer.rg`.
- [ ] Add low-level built-in primitives (`sys_open`, `sys_close`, `sys_read_fd`, `sys_write_fd`, `sys_poll`, `sys_kill`, `sys_call`, `sys_deadline_ms`, `sys_remaining_ms`) and `with timeout <expr> do <body>` (plus `with region <r>, timeout <t> do <body>`) to `src/main/ridgun/lib/parser.rg`, `src/main/ridgun/lib/typecheck.rg`, `src/main/ridgun/lib/analyzer.rg`, `src/main/ridgun/lib/formatter.rg`, and `src/main/ridgun/lib/vm.rg`.
- [ ] Implement the native runtime kernel support and lowering in `src/main/ridgun/lib/compiler.rg`, `src/main/ridgun/lib/x86_64.rg`, and `src/main/ridgun/lib/arm64.rg`.
- [ ] Increment the version (`+0.0.1`) in `build.rg`, `src/main/ridgun/ridgunc/main.rg`, `src/main/ridgun/stable/main.rg`, `README.md`, and `harness/`.
- [ ] Rebuild self-hosted `bin/ridgunc` and `bin/stable`, add automated tests in `src/test/ridgun/test lib and plugins.rg`, and update `harness/`.

## Progress log (append-only, newest last)
- 2026-10-21: Created `FR-COMP-007` and `TASK-0012`.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-007-low-level-posix-fd-poll-syscalls-and-with-timeout-blocks.md`

## Verification performed (command → result, newest last)
- Pending implementation.

## Exact next actions
1. Start `TASK-0012` and inspect `lexer.rg`, `parser.rg`, `typecheck.rg`, `compiler.rg`, `x86_64.rg`, and `arm64.rg`.

## Decisions / open questions
- None.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
