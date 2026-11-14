---
id: TASK-0094
title: Compiler modules are known by where they live, not by a list of names
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
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK-0094 — Compiler modules are known by where they live, not by a list of names

## Goal (one sentence)
`parser.ridgun` decides that a module belongs to the compiler from the folder it is loaded from, so a new compiler module needs no edit to a list.

## Why
`is core compiler mod` in `parser.ridgun` lists the compiler's modules by name (ast, lexer, parser, analyzer, typecheck, compiler, elf64, x86_64, arm64, llvm, macho64, pe64, wasm32, wasm, formatter, prelude). It is used in seven places: import resolution, library loading and the import aliases (`add mod import`).

A compiler module missing from the list breaks silently. TASK-0087 hit it: with `wasm` not listed, a program that imports `elf64` before `wasm` cannot see the NIR types inside `wasm` ("unknown constructor 'NLabel'", "`__unimported__.RLabelEntry`"). The fix was to add `wasm32` and `wasm` to the list. That is a patch: the next backend will fail the same way. Also, a user module with one of these names (for example its own `parser` or `wasm`) is taken for the compiler's.

## Plan
- [ ] Read the seven uses of `is core compiler mod` and write down what each one needs: is the module the compiler's, or is it a module already loaded with the compiler?
- [ ] Choose the rule: a module is the compiler's when it resolves to a file under the compiler's own `src/main/ridgun/lib/` (or the bundle that ships with `ridgunc`), not by name. Record it in an ADR if it changes how user modules with these names resolve.
- [ ] Replace the list with that rule. Keep `prelude` working.
- [ ] A test: a new module in the compiler's lib folder, imported after `elf64`, sees the NIR types without any edit to `parser.ridgun`. A user module named like a compiler module resolves to the user's file.
- [ ] Bootstrap: the change is in the parser, so stage 1 must build with the old rule; check the fixed point, the suite, the unit tests and libs.

## Progress log (append-only, newest last)
- 2026-11-14: Created after TASK-0087. The patch (`wasm32` and `wasm` added to the list) is in 1.0.11, commit a96dfa0.

## Files changed (keep current)
-

## Verification performed (command → result, newest last)
-

## Exact next actions
1. Read the seven uses of `is core compiler mod` (`parser.ridgun` lines 4292, 4312, 4390, 4440, 4519, 4539, 4745 in 1.0.11).

## Decisions / open questions
- How does `ridgunc.wasm` (TASK-0090) know its lib folder, with no file system of its own? The rule must also work for the compiler's modules bundled into the binary.

## Definition of done checklist
- [ ] requirements referenced are `implemented`  - [ ] tests automated & green
- [ ] security entries updated  - [ ] docs INDEX updated  - [ ] coverage matrix regenerated
