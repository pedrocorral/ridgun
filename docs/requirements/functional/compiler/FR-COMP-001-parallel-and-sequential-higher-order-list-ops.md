---
id: FR-COMP-001
title: First-Class Functions and Parallel vs Sequential Higher-Order List Operations
status: implemented
priority: must
created: 2026-10-17
updated: 2026-10-17
depends_on: []
verified_by: []
---
# FR-COMP-001 — First-Class Functions and Parallel vs Sequential Higher-Order List Operations

## Statement
The `ridgunc` compiler and runtime SHALL support passing functions as first-class values (`RVal::Fn`) and provide built-in higher-order collection operations that are **parallel by default** (`map`, `filter`) alongside explicit **sequential** counterparts (`seq_map`, `seq_filter`, `fold`).

## Rationale
In a pure functional language like Ridgun, applying a pure function `f` to every element of a list `[a]` has no inter-element data dependencies. Making `map` and `filter` parallel by default aligns with Ridgun's implicit parallelism philosophy (`where`-DAGs), while providing `seq_map` and `seq_filter` when deterministic sequential side-effect ordering (e.g. I/O) or tiny-list low-overhead execution is desired.

## Functional Specification

### 1. First-Class Function Values (`RVal::Fn`)
- Referencing a top-level function identifier `f` in argument position (with 0 arguments applied when `arity(f) >= 1`) SHALL evaluate to a first-class function value `RVal::Fn("f")` rather than invoking `rg_fn_f()`.
- Runtime invocation `rg_call_fn(fn_val, &[arg1, ...])` dispatches dynamically to the compiled function `rg_fn_<f>`.

### 2. Parallel-by-Default Higher-Order Built-ins
- **`map : (a => b) [a] => [b]`** (and natural-language alias `op :: map (a => b) over [a] => [b]`):
  - Evaluates `f x` concurrently across the elements of `xs` (using parallel worker threads when `len(xs)` exceeds the parallel grain threshold, preserving original list order `[f x_0, f x_1, ..., f x_{n-1}]`).
- **`filter : (a => Bool) [a] => [a]`** (and `op :: filter [a] with (a => Bool) => [a]`):
  - Evaluates predicate `p x` concurrently across the elements of `xs` and retains elements where `p x == True` in their original relative order.

### 3. Explicit Sequential Higher-Order Built-ins
- **`seq_map : (a => b) [a] => [b]`**:
  - Evaluates `f x` strictly left-to-right on the current thread from index `0` to `n - 1`.
- **`seq_filter : (a => Bool) [a] => [a]`**:
  - Evaluates predicate `p x` strictly left-to-right on the current thread.
- **`fold : (b a => b) b [a] => b`** (left fold):
  - Evaluates accumulator `acc = f acc x` sequentially from left to right starting from initial value `init`.

## Acceptance Criteria
- AC1: Given `fn :: square Int => Int` (`square x = x * x`), both `map square [1, 2, 3, 4]` and `seq_map square [1, 2, 3, 4]` evaluate to `[1, 4, 9, 16]`.
- AC2: Given `fn :: is_even Int => Bool` (`is_even x = (x % 2) == 0`), both `filter is_even [1, 2, 3, 4]` and `seq_filter is_even [1, 2, 3, 4]` evaluate to `[2, 4]`.
- AC3: Given `fn :: add Int Int => Int`, `fold add 0 [1, 2, 3, 4]` evaluates to `10`.
