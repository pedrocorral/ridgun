---
id: ADR-0001
title: Decouple stable Build Tool from ridgunc Compiler Internals
status: accepted
date: 2026-10-23
supersedes: []
affects:
  - FR-COMP-006
  - FR-TOOL-001
  - FR-TOOL-002
  - FR-TOOL-003
  - src/main/ridgun/stable/main.rg
---
# ADR-0001 — Decouple `stable` Build Tool from `ridgunc` Compiler Internals

## Context
Previously, `src/main/ridgun/stable/main.rg` directly imported the full compiler pipeline (`ast`, `lexer`, `parser`, `analyzer`, `typecheck`, `compiler`, `vm`, and transitively `elf64`, `x86_64`, and `arm64`). As a consequence, every build of `stable` recompiled ~10,600 lines of compiler and machine-code backend sources into `bin/stable`, duplicating `bin/ridgunc` and taking ~2 minutes per build even when `stable` itself had not changed.

## Options considered
1. **Keep `ridgunc` internals embedded as library imports inside `stable`**: zero subprocess overhead, but duplicates compilation of the entire compiler/backends into two binaries and couples build-tool evolution to compiler internals.
2. **Decouple `stable` from `ridgunc` and invoke the `ridgunc` CLI binary**: `stable` owns project configuration (`build.rg`), formatting (`formatter.rg`), scaffolding, dependency management, plugins, and task orchestration, and invokes `ridgunc` (`check`, `compile`, `build`, `build --lib`, `build --so`) for compilation tasks.

## Decision
Adopt **Option 2**. Remove all compiler module imports (`ast`, `lexer`, `parser`, `analyzer`, `typecheck`, `compiler`, `vm`) from `src/main/ridgun/stable/main.rg`. `stable` resolves the `ridgunc` binary (via `$RIDGUNC`, the sibling directory of `stable`'s executable path, `./bin/ridgunc`, `./target/ridgunc`, or `PATH`) and delegates typechecking, bytecode emission, and ELF64 executable/library compilation to `ridgunc`.

## Consequences
- Requirements to update: `FR-TOOL-002`, `FR-TOOL-003`, `docs/requirements/INDEX.md`, `docs/requirements/decisions/INDEX.md`
- Tests to update: none (`src/test/ridgun/test lib and plugins.rg` continues to verify all `stable` CLI and REPL behaviours end-to-end)
- Code to update: `src/main/ridgun/stable/main.rg`
