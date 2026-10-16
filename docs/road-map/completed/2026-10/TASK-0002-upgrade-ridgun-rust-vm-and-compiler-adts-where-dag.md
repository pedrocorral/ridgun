---
id: TASK-0002
title: Upgrade Ridgun Rust VM and Compiler (ADTs, where/|| DAGs, Regions, Channels, Scheduler)
status: completed
created: 2026-10-16
completed: 2026-10-16
requirements: []
tests: []
security: []
context_files: [docs/lang/spec.md, docs/etc/next_gen_architecture.md, src/main/rust/parser.rs, src/main/rust/typecheck.rs, src/main/rust/compiler.rs, src/main/rust/vm.rs, src/main/rust/scheduler.rs, src/main/rust/greenthread.rs, src/main/rust/mailbox.rs]
scope: [src/main/rust/, tests/integration.rs]
owner: agent-001
claimed: 2026-10-16T17:42:38Z
claimed_by: agent gemini@solarfall
policy: anarchy
---
# TASK-0002 — Upgrade Ridgun Rust VM and Compiler (ADTs, where/|| DAGs, Regions, Channels, Scheduler)

## Goal (one sentence)
Upgrade the Rust compiler and VM to support ADTs/tuples/cons-patterns, `where`/`||` parallel DAG execution with static mutation freeze, lexical region memory, typed channels with affine moves, reduction-counted scheduler integration, and `--seed` deterministic simulation.

## Plan
- [x] Step 1: Complete runtime ADT (sum/product `type`), Tuple, and `ListCons` `(x:xs)` / `[]` pattern matching & construction in parser, compiler, and VM.
- [x] Step 2: Implement `where` (`expr -> var`) and `||` parallel blocks with static DAG cycle detection (`CyclicWhereDependencyError`) and interprocedural mutation freeze checking (`ParallelMutationConflictError`).
- [x] Step 3: Implement Lexical Region memory arena (`Region`) in the VM with function-scoped bump allocation, return value promotion, and tail-call region reset.
- [x] Step 4: Integrate the reduction-counted `Scheduler` with `VM` execution, deterministic `--seed` simulation mode, and typed `Channel` operations with affine move checking (`UseAfterChannelSendError`).
- [x] Step 5: Verify all existing + new unit and integration tests pass with `cargo test` and `aix docs validate`.

## Progress log (append-only, newest last)
- 2026-10-16: Task created and planned from `docs/lang/spec.md` and `docs/etc/next_gen_architecture.md`.
- 2026-10-16: Implemented `region.rs` (Lexical Region bump arenas + PingPongArena), `channel.rs` (typed MPMC channels with backpressure & affine move checks), `analyzer.rs` (`FnStaticSummary`, `WhereDag` Kahn topological stages, `CyclicWhereDependencyError`, `ParallelMutationConflictError`, `UseAfterChannelSendError`), upgraded `lexer.rs`, `parser.rs`, `typecheck.rs`, `compiler.rs`, `vm.rs`, `scheduler.rs`, and `main.rs`, and added 12 new end-to-end integration tests in `tests/integration.rs`. All 147 tests pass with 0 warnings.

## Files changed (keep current)
- `src/main/rust/lib.rs`, `src/main/rust/main.rs`, `src/main/rust/lexer.rs`, `src/main/rust/parser.rs`, `src/main/rust/typecheck.rs`, `src/main/rust/compiler.rs`, `src/main/rust/vm.rs`, `src/main/rust/scheduler.rs`, `src/main/rust/region.rs`, `src/main/rust/channel.rs`, `src/main/rust/analyzer.rs`
- `tests/integration.rs`
- `docs/lang/spec.md`, `editors/vscode/syntaxes/ridgun.tmLanguage.json`
- `docs/INDEX.md`, `docs/lang/INDEX.md`, `docs/etc/INDEX.md`, `docs/dev/INDEX.md`, `docs/dev/disabled/INDEX.md`, `docs/dev/sast_policy.md`

## Verification performed (command → result, newest last)
- `cargo test` → 126 passed (108 unit + 18 integration)
- `aix docs validate` → 0 errors, 0 warnings
- `cargo test` → 147 passed (117 unit + 30 integration), 0 warnings
- `python3 -m json.tool editors/vscode/syntaxes/ridgun.tmLanguage.json > /dev/null` → exit 0
- `aix docs validate` → 0 errors, 0 warnings

## Exact next actions
1. Ready for Option 2 (Self-hosted Ridgun bytecode compiler & meta-circular VM written in `.rg`) or further language features whenever requested.

## Decisions / open questions
- User selected Option 1: Upgrade the Rust VM/Compiler first.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
