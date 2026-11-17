---
id: TASK-0102
title: Separate compilation with explicit function interfaces and compiled libraries (Vonkeep request 5, options C and D); needs an ADR first
status: pending             # pending | going-on | blocked | completed
created: 2026-11-17
completed:
requirements: []            # FR-*/NFR-* this task delivers or touches
tests: []                   # TS-* to automate
security: []                # VUL-* to address
context_files: []           # THE ONLY files an agent must read to work on this task
scope: []                   # paths/globs this task will change (aix task start warns when two going-on tasks overlap)
owner:                      # the seat that holds it (agent-001 ...), signed by aix task start
claimed:
claimed_by:                 # tool user@host behind the seat at that moment (stays after the seat is released)
policy:                     # a cycle for this task only (hotfix, release, ...); empty = the project's (aix policy)
---
# TASK — A library is compiled once into a unit with an explicit interface per 

## Goal (one sentence)
A library is compiled once into a unit with an explicit interface per function (type, arity, borrow mask, tail-call status) and programs link it instead of compiling it again.

## Plan
- [ ] ADR first: what the interface of a function is, how borrow masks and tail calls are decided without the callers, how global tables (function numbers, string pool, field map) merge at link time, what optimizations across units are kept.
- [ ] New `.ridgunlib` format: interface plus compiled code (option D can use the serialized front end or lowered code as a first form).
- [ ] Migrate `stable build lib` and the libraries.
- [ ] Segment tests: a library change recompiles the library once; programs that use it only link.

## Progress log (append-only, newest last)
- 2026-11-17: Created from Vonkeep request 5 (options C and D). Other compiled languages do this (Rust crates, OCaml .cmi/.cmx, Swift modules, C object files); the cost is that the compiler is whole-program today. See docs/etc/incremental_and_separate_compilation.md.

## Exact next actions
1. Read `docs/etc/incremental_and_separate_compilation.md` (options A to D, measurements, acceptance).
