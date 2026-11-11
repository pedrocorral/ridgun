---
id: ADR-0006
title: Opaque types are declared with one keyword per type, checked when names are resolved
status: accepted
date: 2026-11-12
supersedes: []
affects:
  - FR-COMP-025
  - src/main/ridgun/lib/parser.rg
---
# ADR-0006 — Opaque types: one keyword per type, checked when names are resolved

## Context
- Any module that can name a type can also call its constructors, read its fields and update it. A library
  cannot make a value that only it can create (feature request of 2026-11-12, "opaque types").
- Several files can declare the same module and share its names.
- The parser resolves every constructor, field and function name to one global name per module context before
  type checking. After that step a name no longer says which module wrote it.

## Options considered
1. **`opaque type T = ...`:** the whole type is opaque outside its module.
2. **`private` per constructor or field:** a sum type can expose some variants, a record some fields.
3. **An export list per module:** the module names what other modules see.

## Decision
Adopt **Option 1**.
- It covers every case in the request and adds one word to the grammar.
- Option 2 can be added later on top of it without breaking code that uses option 1.
- Option 3 changes every module that exists today.

The rule is checked in the parser, in the step that resolves names: each function is resolved in its own
module's context, so the step knows both the module that uses a name and the module that owns it. A function
outside the owning module that uses a constructor, accessor or `with` field of an opaque type becomes a compile
error. A cost appears only when a program declares an opaque type.

## Consequences
- The defining module, with every file that declares it, is the trusted area. A library that wants a smaller one
  puts the type in a module of its own.
- Printing still shows the content (FR-COMP-025, known limit).
- A native `.so` called from another language does not check the rule.
