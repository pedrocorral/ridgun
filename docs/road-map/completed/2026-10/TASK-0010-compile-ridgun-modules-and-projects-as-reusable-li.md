---
id: TASK-0010
title: Compile Ridgun modules and projects as reusable libraries (.rglib and ELF64 .so)
status: completed
created: 2026-10-21
completed: 2026-10-21
requirements:
  - FR-COMP-006
tests: []
security: []
context_files:
  - docs/requirements/functional/compiler/FR-COMP-006-library-compilation-rglib-and-elf64-shared-object.md
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/elf64.rg
  - src/main/ridgun/stable/main.rg
scope:
  - src/main/ridgun/ridgunc/main.rg
  - src/main/ridgun/lib/compiler.rg
  - src/main/ridgun/lib/elf64.rg
  - src/main/ridgun/lib/x86_64.rg
  - src/main/ridgun/lib/arm64.rg
  - src/main/ridgun/stable/main.rg
  - src/test/ridgun/
  - docs/
owner: agent-001
claimed: 2026-10-21T14:55:15Z
claimed_by: agent gemini@solarfall
policy:                     # a cycle for this task only
---
# TASK-0010 — Compile Ridgun modules and projects as reusable libraries (`.rglib` and ELF64 `.so`)

## Goal (one sentence)
Deliver `FR-COMP-006` so `ridgunc` and `stable` can compile Ridgun modules and projects without a `main` function into reusable `.rglib` library bundles (importable by other Ridgun projects) and native Linux ELF64 `ET_DYN` shared objects (`.so`).

## Plan
- [x] Update `src/main/ridgun/lib/compiler.rg` so library compilation (`lower_library_to_native` / `emit_rglib_file` / `build_native_library`) does not require `main` and preserves all top-level `fn ::`, `op ::`, `type`, and `expand type` definitions without tree-shaking them away.
- [x] Update `src/main/ridgun/lib/elf64.rg`, `src/main/ridgun/lib/x86_64.rg`, and `src/main/ridgun/lib/arm64.rg` to support emitting ELF64 shared objects (`e_type = 3` / `ET_DYN`) for `.so` outputs.
- [x] Update `src/main/ridgun/ridgunc/main.rg` to support `ridgunc build --lib <input.rg> [-o <out.rglib|out.so>]`.
- [x] Update `src/main/ridgun/stable/main.rg` to support `project kind = "lib"` / `"both"` in `build.rg`, `stable built lib` (emitting `target/lib<name>.rglib` and `target/lib<name>.so`), and `stable new lib <name>`.
- [x] Support importing `.rglib` bundles (`target/lib<name>.rglib` and `.stable/deps/*/target/lib<name>.rglib`) when resolving `import <name>`.
- [x] Add automated tests in `src/test/ridgun/test core language.rg` verifying `--lib` `.rglib` and `.so` compilation and importing a compiled `.rglib` library.
- [x] Bootstrap Stage 1 & Stage 2 `target/ridgunc` and `target/stable`, and update documentation and books.

## Progress log (append-only, newest last)
- 2026-10-21: Created `TASK-0010` and `FR-COMP-006`.
- 2026-10-21: Implemented `.rglib` and ELF64 `ET_DYN` (`.so`) compilation in `compiler.rg`, `elf64.rg`, `x86_64.rg`, `arm64.rg`, `parser.rg`, `ridgunc/main.rg`, and `stable/main.rg`, plus parser edge-case fixes (`can_absorb_mixfix_conj` and `has_longer_arity_prefix` before `is_std_builtin`). Rebuilt `bin/ridgunc` and `bin/stable` and verified `5/5` test suites.

## Files changed (keep current)
- `docs/requirements/functional/compiler/FR-COMP-006-library-compilation-rglib-and-elf64-shared-object.md`
- `src/main/ridgun/lib/parser.rg`
- `src/main/ridgun/lib/compiler.rg`
- `src/main/ridgun/lib/elf64.rg`
- `src/main/ridgun/lib/x86_64.rg`
- `src/main/ridgun/lib/arm64.rg`
- `src/main/ridgun/ridgunc/main.rg`
- `src/main/ridgun/stable/main.rg`
- `src/test/ridgun/test core language.rg`
- `src/test/ridgun/test lib and plugins.rg`

## Verification performed (command → result, newest last)
- `./bin/stable test` → `5 passed, 0 failed` (`test basics.rg`, `test core language.rg`, `test lib and plugins.rg`, `test parallel and tensors.rg`, `test strings.rg`).

## Exact next actions
1. Proceed to `TASK-0011`.

## Decisions / open questions
- None.

## Definition of done checklist
- [x] requirements referenced are `implemented`  - [x] tests automated & green
- [x] security entries updated  - [x] docs INDEX updated  - [x] coverage matrix regenerated
