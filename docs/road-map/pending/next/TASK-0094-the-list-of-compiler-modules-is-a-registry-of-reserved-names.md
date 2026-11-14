---
id: TASK-0094
title: The list of compiler modules is a registry of reserved names, checked at compile time
status: pending             # pending | going-on | blocked | completed
created: 2026-11-14
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: [src/main/ridgun/lib/parser.ridgun, docs/road-map/completed/2026-11/TASK-0087-translate-the-nir-to-wasm-instructions.md]
scope: [src/main/ridgun/lib/parser.ridgun]
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (# TASK-0094 — The list of compiler modules is a registry of reserved names

## Goal (one sentence)
`is core compiler mod` in `parser.ridgun` stays the one list of the compiler's modules, and the compiler stops with a clear error when the list and the modules disagree, or when a user module takes one of its names.

## Why
The list (ast, lexer, parser, analyzer, typecheck, compiler, elf64, x86_64, arm64, llvm, macho64, pe64, wasm32, wasm, formatter, prelude) decides how a module is loaded: a listed module is pasted into one flat scope, any other gets its own module scope. A compiler module missing from the list is loaded with its own scope and cannot see the types of the flat modules it imports. TASK-0087 hit it: with `wasm` not listed, 73 type errors ("unknown constructor 'NLabel'", "`__unimported__.RLabelEntry`") and no word about the cause. The patch was to add `wasm32` and `wasm`.

The same list names what is reserved: a user module called `parser` or `wasm` is silently taken for the compiler's. Only the compiler's own repository imports these modules today.

## Plan
- [ ] **Missing from the list.** A module loaded from the folder that holds `parser.ridgun` (the compiler's `src/main/ridgun/lib/`) and not in the list stops the build: `module 'X' is in the compiler's lib folder but not in the list of compiler modules (is core compiler mod, parser.ridgun)`.
- [ ] **Reserved name.** A module file elsewhere whose name is in the list stops the build: `module name 'X' is reserved for the compiler; rename the module`. Importing a compiler module stays allowed.
- [ ] Tests: a temporary module in a copy of the lib folder, not listed, gives the first error; a user `parser.ridgun` next to a program gives the second; the compiler and its tests still build.
- [ ] Document the reserved names in the language docs (modules and imports).
- [ ] Bootstrap: the change is in the parser, so stage 1 builds with the old parser; check the fixed point, the suite, the unit tests and libs.

## Progress log (append-only, newest last)
- 2026-11-14: Created after TASK-0087. The patch (`wasm32` and `wasm` added to the list) is in 1.0.11, commit a96dfa0.
- 2026-11-14: The user chose to keep the list and check it, and to use it as the registry of reserved names, instead of finding compiler modules by folder. How `ridgunc.wasm` reads libraries is ADR-0012 (TASK-0089, TASK-0091), not this task.

## Files changed (keep current)
-

## Verification performed (command → result, newest last)
-

## Exact next actions
1. Read the seven uses of `is core compiler mod` (`parser.ridgun` lines 4292, 4312, 4390, 4440, 4519, 4539, 4745 in 1.0.11) and find where a module's file and folder are known.

## Decisions / open questions
- None.

to the binary.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
