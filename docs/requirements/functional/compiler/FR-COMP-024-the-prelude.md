---
id: FR-COMP-024
title: The Prelude
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-10
updated: 2026-11-10
depends_on: [FR-COMP-012]
related: [ADR-0004]
verified_by: [TS-COMP-024]
---
# FR-COMP-024 — The Prelude

## Statement
Every Ridgun program SHALL be able to call a small set of generic list and string helpers without an `import`. The set is called the prelude.

```ridgun
fn :: list len [A] => Int
fn :: list reverse [A] => [A]
fn :: list take [A] Int => [A]             -- the first n elements (none when n <= 0)
fn :: list drop [A] Int => [A]             -- all but the first n elements
fn :: list nth or [A] Int A => A           -- element i, or the default when i is out of range
fn :: list last or [A] A => A              -- the last element, or the default when the list is empty
fn :: list contains [A] A => Bool
fn :: str join [String] String => String   -- the strings with the separator between them
```

## Requirements
1. **Always there.** `ridgunc` adds the prelude to every program as the module `prelude`. A program SHALL NOT need `import prelude`; if it writes it anyway, the line does nothing.
2. **Lowest priority.** A name is looked up in the prelude only when it is defined neither in the current module nor in any module the current module imports, directly or transitively. Any other definition of the same name wins, with no ambiguity error. Existing programs and libraries therefore keep their meaning.
3. **Generic.** Each helper works for any element type, including tuples, records and ADTs, with `==` as the equality of `list contains`.
4. **Cost.** A prelude helper costs what a hand-written copy for one element type costs:
   - `list len`, `list reverse` and `str join` run in linear time, as tail calls;
   - a program that calls none of them is no larger than before.
5. **Visible.** `ridgunc prelude` prints the prelude's source.

## Rationale
- ridgunc and stable held about 220 small helpers, many of them copies of the same function for another element type: 15 copies of "reverse a list", for example.
- libs repeats the pattern too: `list take` and `list str take`, `list reverse` and `list str reverse`.
- The compiler cannot import libs, because libs is compiled with the compiler. Basic helpers therefore belong to the language.
- Helpers for a domain stay in libs, for example `math` or `json`.

## Out of scope
- Helpers that take a function (`list any`, `list all`).
- Maps and sets.

## Implementation status
Implemented in 0.9.54 (TASK-0070).
- The source is `prelude source` in `src/main/ridgun/lib/parser.ridgun`. `load rg with libs` appends it after the imports, between module markers.
- The lowest-priority lookup is in the module resolver: the `prelude tier` functions after the transitive imports.
- A prelude function never counts as a name collision. When another module defines the same name, that module keeps the plain name and the prelude's function is renamed `prelude.<name>`, found only in the last tier.
- In 0.9.54 it counted as a collision, so `import list` from libs broke `list nth or`: the operator word `or` inside the name is matched against the plain name. Fixed in 0.9.55.
- 0.9.55 (TASK-0070, phase B): the compiler uses the prelude in place of 36 per-type copies.
- Test: `tests/cases/modules/prelude_*.ridgun`.
