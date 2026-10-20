---
id: FR-COMP-002
title: Ridgun Memory Management (RMM) — RMM1 (CMM Linear & Conditional) and RMM2 (Assignment & Cascaded Structure Counting)
status: implemented
priority: must
created: 2026-10-19
updated: 2026-10-19
depends_on: []
verified_by: []
---
# FR-COMP-002 — Ridgun Memory Management (RMM): RMM1 (CMM) and RMM2

## Statement
The `ridgunc` native compiler SHALL manage heap memory deterministically without a tracing Garbage Collector (GC) through **Ridgun Memory Management (RMM)**, structured into two active policies (with **RMM3** reserved for a future aggressive optimization pass):
1. **`RMM1` — Compiled Memory Management (CMM Linear + Conditional)**:
   - For statically known control flow over non-nested bindings, the compiler determines the exact last-use statement of every local variable at compile time, emitting `rg_cmm_move` on returned variables, unconditional `rg_cmm_drop` when no compile-time may-aliases remain live, and **Conditional CMM pointer-identity guards** (`rg_cmm_drop_unless(&mut lv_x, &[&lv_c, ...])`, i.e. `if ptr(x) != ptr(c) { free(x) }`) when branching aliases (`c = choose_list cond a b`) have overlapping lifetimes.
2. **`RMM2` — Assignment & Cascaded Structure Counting (Anonymous Functions, Nested Containers & Multi-thread)**:
   - For dynamic control flow (anonymous functions / higher-order callbacks), nested data structures (`xs = [a, b, ..., z]`, `xs[3] = a`), and multi-threaded sharing:
     - Primitive scalars (`Int`, `Real`, `Bool`, `Unit`) SHALL NOT be reference-counted.
     - Heap structures (`List`, `Tuple`, `Adt`, `Tensor`, `Str`) SHALL carry their own counter (`rc`), incremented (`+1`) on variable or slot assignment (`b = a`, `xs[3] = a`), untouched (`+0`) on read-only borrows, moved without decrement on `return`, and decremented (`-1`) at variable death (when not returned).
     - When a parent structure's counter reaches `0`, it SHALL be destroyed and SHALL decrement (`-1`) each of its direct child structures one by one, recursively freeing any child whose counter reaches `0`.

## Rationale
Pure static liveness (`RMM1` / CMM) eliminates runtime reference counting completely when the execution graph and variable relationships are statically visible at compile time (including static branching such as `c = choose_list cond a b` via pointer-identity guards `ptr(x) != ptr(c)`). When anonymous functions make control flow opaque at compile time or when structures nest inside other structures (`xs = [a..z]`, `xs[3] = a`), `RMM2` provides a unified, leak-free, and use-after-free-proof mechanism across both single-threaded and multi-threaded execution without touching counters on read-only operations or function returns.

## Functional Specification

### 1. Policy `RMM1`: Linear & Conditional CMM (`rg_cmm_move`, `rg_cmm_drop`, `rg_cmm_drop_unless`)
- For every statement sequence (`EBlock`, `EWhere`, `FnCase`), the compiler SHALL compute the static last-use statement of each local variable `v` and build the compile-time **Ancestor May-Alias Table (`RCmmAlias`)**.
- Immediately after the statement containing the last use of any local variable `x`:
  - **Linear CMM (`LivePeers(x) == []`)**: If no other variable sharing an ancestor with `x` is live after that statement, the compiler SHALL emit `rg_cmm_drop(&mut lv_x)`.
  - **Conditional CMM (`LivePeers(x) == [y_1, ..., y_k]`)**: If variables `y_1, ..., y_k` sharing a compile-time ancestor with `x` remain live after that statement, the compiler SHALL emit `rg_cmm_drop_unless(&mut lv_x, &[&lv_y1, ...])` (`if ptr(x) != ptr(y_1) && ... { free(x) }`).
- On `return v`, the compiler SHALL emit `rg_cmm_move(&mut lv_v)` so the returned variable is transferred without deallocation.

### 2. Canonical `choose_list` Lifecycle Trace (`RMM1`)
Given:
```ridgun
a = make_a ()
b = make_b ()
c = choose_list cond a b
print_list a
consume_list c
```
- After `c = choose_list cond a b`: `b` has no further uses while `c` is live $\rightarrow$ `rg_cmm_drop_unless(&mut lv_b, &[&lv_c])`.
- After `print_list a`: `a` has no further uses while `c` is live $\rightarrow$ `rg_cmm_drop_unless(&mut lv_a, &[&lv_c])`.
- After `consume_list c`: `c` has no further uses and no live peers $\rightarrow$ unconditional `rg_cmm_drop(&mut lv_c)`.

### 3. Policy `RMM2`: Assignment & Cascaded Structure Counting (`CmmBox<T>`)
- Primitive types (`Int`, `Real`, `Bool`, `Unit`) are unboxed stack values with no counter.
- Heap structures (`CmmBox<T>`) start with `links = 1` upon allocation:
  - Assigning `b = a` or `xs[3] = a` (or inserting `a` into `xs = [a, b, ..., z]`) increments `a`'s link count by `+1`.
  - Returning a variable (`return x`) moves `x` without decrementing its link count.
  - Dropping a non-returned variable decrements its link count by `-1`; when a parent container's link count reaches `0`, it frees the container and decrements (`-1`) each child element one by one, freeing any child whose count reaches `0`.

## Acceptance Criteria
- AC1: `ridgunc` implements `RMM1` (CMM liveness + `RCmmAlias` conditional pointer-identity guards) and `RMM2` (`CmmBox<T>` assignment & cascaded child teardown).
- AC2: `cmm_trace_elegir True` produces `(2, 1, 1, 0, 1, 1)`, `cmm_trace_elegir False` produces `(2, 2, 1, 0, 1, 1)`, and `cmm_trace_cascada` passes in `src/test/ridgun/test_core_language.rg`.
- AC3: Self-hosted Stage 1 and Stage 2 bootstrap of `ridgunc` and `stable` and all 4 Ridgun test suites pass with 0 errors.
