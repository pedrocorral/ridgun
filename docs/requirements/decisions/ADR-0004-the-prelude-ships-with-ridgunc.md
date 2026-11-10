---
id: ADR-0004
title: The prelude ships with ridgunc, at the lowest lookup priority
status: accepted
date: 2026-11-10
supersedes: []
affects:
  - FR-COMP-024
  - FR-COMP-012
  - src/main/ridgun/lib/parser.rg
---
# ADR-0004 — The prelude ships with ridgunc, at the lowest lookup priority

## Context
- ridgunc and stable held about 220 small helpers. Many were copies of one function for another element type: 15 copies of "reverse a list", 9 of "list length", and others for take, drop, join and "is it in the list".
- libs repeats the pattern too: `list take` and `list str take`, `list reverse` and `list str reverse`.
- The compiler cannot import libs: libs is compiled with the compiler, and since ADR-0003 it arrives only through omni.

## Options considered
1. **Generic helpers in libs:** this leaves the compiler with its copies, and every program still needs `import list`.
2. **Builtins written in the runtime:** each helper needs code in every backend, for little gain over Ridgun source.
3. **A prelude in Ridgun source, shipped with ridgunc:** it is added to every program as the module `prelude` and found last.

## Decision
Adopt **Option 3**.
- **The source:** `prelude source` in `src/main/ridgun/lib/parser.rg`. The text is part of the compiler, so it needs no file at run time.
- **How it is added:** `load rg with libs` adds the prelude between module markers, after the imports.
- **Lookup:** a name is looked up in the prelude only after the own module, the direct imports and the transitive imports (FR-COMP-012). That last tier is the `prelude tier` functions.
- **Names that already exist:**
  - A name that libs, a program or a library already defines keeps its meaning, so nothing existing changes and nothing becomes ambiguous.
  - `import prelude` is accepted and does nothing.
- **Size:** unused prelude functions are not emitted, so a program that calls none of them keeps its size.
- **What goes in:** only helpers that every program needs and that work the same for any element type. Domain helpers stay in libs.

## Consequences
- **Requirements:** FR-COMP-024, and Tier 4 in `docs/lang/spec.md`.
- **Tests:**
  - `tests/cases/lists/prelude_*.rg`;
  - `tests/cases/perf/prelude_helpers_are_linear.rg`;
  - toolchain check tc10 in `tests/run.rg`.
- **Code:**
  - In 0.9.54, `parser.rg` adds the prelude and `ridgunc` gets the `prelude` command.
  - In 0.9.55, the compiler and stable replace their copies with prelude calls. That step needs a compiler that already has the prelude, so it is a separate bootstrap.
- **libs:** can drop its per-type copies, and its typed names can call the prelude. This is noted in the compiler team notes.
