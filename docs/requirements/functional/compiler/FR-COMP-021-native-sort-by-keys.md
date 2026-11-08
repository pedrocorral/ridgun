---
id: FR-COMP-021
title: Native Sort by Keys
type: functional
domain: compiler
status: implemented
priority: must
created: 2026-11-08
updated: 2026-11-08
depends_on: []
related: [FR-COMP-020]
verified_by: [TS-COMP-021]
---
# FR-COMP-021 — Native Sort by Keys

## Statement
Ridgun SHALL provide two native, stable sorts of a list by a parallel list of keys:

```ridgun
fn :: sort by ints [A] [Int] => [A]
fn :: sort by texts [A] [String] => [A]
```

`sort by ints xs keys` returns the elements of `xs` ordered by `keys`: element `i` of `xs` has key `i` of `keys`. Sorting a list by itself is `sort by ints xs xs`.

## Requirements
1. **Order.** `sort by ints` orders by the Int value of the keys. `sort by texts` orders like `<` on Strings: byte by byte, and a prefix comes first (`"a" < "ab"`, `"Z" < "a"`, `"z" < "é"`).
2. **Stable.** Elements with equal keys keep their order from `xs`.
3. **Result.** The result is a new list. `xs` and `keys` do not change. Each element of the result holds one more reference (RMM).
4. **Lengths.** When `xs` and `keys` have different lengths, the program stops with `runtime error: sort by: the lists have different lengths` on stderr and exit status 1.
5. **Any list.** The sorts work on any list, also a list built at run time (`[x] :: acc`) or the tail of another list.
6. **Speed.** 100,000 elements: under 100 ms for `sort by ints` with the LLVM backend.
7. **Backends.** LLVM and the pure x86-64 encoder. ARM64 emits a placeholder until its runtime supports lists of this kind.

## Rationale
libs builds grouping, counting and ordering on lists and tensors. Sorting in Ridgun code took 3.3 s (Ints) and 3.9 s (Strings) for 100,000 elements. The compiler team accepted two functions instead of four in its answer to libs (2026-11-07, `agrupar-contar-ordenar-primitivas.md`): `sort ints xs` is `sort by ints xs xs`.

## Out of scope
- Sorting tensors in place.
- A comparison function given by the caller.

## Implementation status
Implemented in 0.9.44 (`NSortBy`): LLVM `@__rg_sort_by`, x86-64 `sortby.s`; ARM64 emits a placeholder. Design and measurements: `docs/etc/gentensor.md`, "Native sort by keys (0.9.44)". Tests: `tests/cases/lists/sort_by_ints_and_texts.rg`, `tests/cases/lists/sort_by_lists_of_different_lengths_fails.rg`, `tests/cases/perf/sort_by_100k_elements.rg`.
