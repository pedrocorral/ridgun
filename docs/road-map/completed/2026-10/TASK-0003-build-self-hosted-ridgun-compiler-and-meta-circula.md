---
id: TASK-0003
title: Build self-hosted Ridgun compiler and meta-circular VM in Ridgun (.rg)
status: completed
created: 2026-10-16
completed: 2026-10-16
requirements: []
tests: []
security: []
context_files: [docs/lang/spec.md, src/main/rust/parser.rs, src/main/rust/typecheck.rs, src/main/rust/compiler.rs, src/main/rust/vm.rs, tests/integration.rs]
scope: [examples/self_hosted_vm.rg, tests/integration.rs, src/main/rust/]
owner: agent-001
claimed: 2026-10-16T18:11:46Z
claimed_by: agent gemini@solarfall
policy: anarchy
---
# TASK-0003 — Build self-hosted Ridgun compiler and meta-circular VM in Ridgun (.rg)

## Goal (one sentence)
Write a self-hosted Ridgun AST compiler and meta-circular bytecode VM in Ridgun itself (`examples/self_hosted_vm.rg`) using Ridgun ADTs, pattern matching, lists, and natural-language operators, and verify it with automated integration tests.

## Plan
- [x] Step 1: Ensure the Rust parser/typechecker/compiler support multi-constructor ADT definitions with shared or nested types (`type Expr`, `type Instr`, `type VmState`) and recursive list/ADT helper functions needed by `examples/self_hosted_vm.rg`.
- [x] Step 2: Implement `examples/self_hosted_vm.rg` in Ridgun containing:
  - `type Expr` (AST for integer literals, local variables, addition, subtraction, multiplication, equality/comparison, conditionals, and recursive calls)
  - `type Instr` (Bytecode instruction set: `IPush`, `ILoad`, `IAdd`, `ISub`, `IMul`, `IEq`, `IJz`, `IJmp`, `ICall`, `IRet`)
  - `compile_expr`: Pure Ridgun compiler translating `Expr` AST into `[Instr]` bytecode
  - `exec_vm`: Meta-circular Ridgun bytecode VM stepping instructions, stack, call frames, and local slots
- [x] Step 3: Add integration tests in `tests/integration.rs` verifying the self-hosted compiler and VM in `examples/self_hosted_vm.rg` and run `cargo test` + `aix docs validate`.

## Progress log (append-only, newest last)
- 2026-10-16: Task created and started (`agent-001`).
- 2026-10-16: Implemented `examples/self_hosted_vm.rg` (AST `type Expr`, bytecode ISA `type Instr`, self-hosted static cost-tier analyzer `analyze Expr cost tier`, AST-to-bytecode compiler `compile Expr into bytecode`, and meta-circular bytecode VM `execute [Instr] with Int` with call stack `ret_pcs` / `saved_args` and parallel `where` verification). Added `test_self_hosted_compiler_and_metacircular_vm` and `test_demo_rg_runs_cleanly` in `tests/integration.rs`.

## Files changed (keep current)
- `examples/self_hosted_vm.rg`
- `src/main/rust/parser.rs`, `src/main/rust/typecheck.rs`, `src/main/rust/vm.rs`, `src/main/rust/main.rs`
- `tests/integration.rs`

## Verification performed (command → result, newest last)
- `cargo run --quiet -- examples/self_hosted_vm.rg` → exit 0 (`56`, `120`, `720`, `55`, `210`)
- `cargo run --quiet -- examples/demo.rg` → exit 0
- `cargo test` → 149 passed (117 unit + 32 integration), 0 warnings

## Exact next actions
1. Task complete.

## Decisions / open questions
- User requested Option 2 (Self-hosted Ridgun compiler and meta-circular VM written in `.rg`).

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
