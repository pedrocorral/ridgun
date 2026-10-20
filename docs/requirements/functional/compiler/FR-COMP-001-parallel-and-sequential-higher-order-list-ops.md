---
id: FR-COMP-001
title: First-Class Functions and Sequential (`map`, `filter`, `fold`) vs Parallel (`||map`, `||filter`) Higher-Order List Operations
status: implemented
priority: must
created: 2026-10-17
updated: 2026-10-20
depends_on: []
verified_by: []
---
# FR-COMP-001 — First-Class Functions and Sequential (`map`, `filter`, `fold`) vs Parallel (`||map`, `||filter`) Higher-Order List Operations

## Statement
The `ridgunc` compiler and runtime SHALL support passing functions as first-class values (`RVal::Fn`) and provide standard **sequential** higher-order collection operations (`map`, `filter`, `fold`) alongside explicit **parallel** counterparts (`||map`, `||filter`) using Ridgun's `||` parallel prefix.

## Rationale
In Ridgun, the `||` token uniformly denotes parallel execution across the language (`|| expr -> var` for parallel DAG bindings, `||.` for closing nested parallel blocks). Making `map` and `filter` standard left-to-right sequential operations while naming their multicore parallel counterparts **`||map`** and **`||filter`** makes parallelism 100% explicit, orthogonal, and visually unmistakable without inventing ad-hoc prefixes (`seq_*` or `par_*`).

## Functional Specification

### 1. First-Class Function Values (`RVal::Fn`)
- Referencing a top-level function identifier `f` in argument position (with 0 arguments applied when `arity(f) >= 1`) SHALL evaluate to a first-class function value `RVal::Fn("f")` rather than invoking `rg_fn_f()`.
- Runtime invocation `rg_call_fn(fn_val, &[arg1, ...])` dispatches dynamically to the compiled function `rg_fn_<f>`.

### 2. Standard Sequential Higher-Order Built-ins (`map`, `filter`, `fold`)
- **`map : (A => B) [A] => [B]`**:
  - Evaluates `f x` strictly left-to-right on the current thread from index `0` to `n - 1`.
- **`filter : (A => Bool) [A] => [A]`**:
  - Evaluates predicate `p x` strictly left-to-right on the current thread and retains elements where `p x == True` in their original relative order.
- **`fold : (B A => B) B [A] => B`** (left fold):
  - Evaluates accumulator `acc = f acc x` sequentially from left to right starting from initial value `init`.

### 3. Parallel Higher-Order Built-ins (`||map`, `||filter`)
- **`||map : (A => B) [A] => [B]`**:
  - Evaluates `f x` concurrently across the elements of `xs` using multicore worker threads (`std::thread::scope` with 64 MB stack per worker when `len(xs) >= 2`), preserving original list order `[f x_0, f x_1, ..., f x_{n-1}]`.
- **`||filter : (A => Bool) [A] => [A]`**:
  - Evaluates predicate `p x` concurrently across the elements of `xs` using multicore worker threads and retains elements where `p x == True` in their original relative order.

## Acceptance Criteria
- AC1: Given `fn :: square Int => Int` (`square x = x * x`), both `map square [1, 2, 3, 4]` and `||map square [1, 2, 3, 4]` evaluate to `[1, 4, 9, 16]`.
- AC2: Given `fn :: is_even Int => Bool` (`is_even x = (x % 2) == 0`), both `filter is_even [1, 2, 3, 4]` and `||filter is_even [1, 2, 3, 4]` evaluate to `[2, 4]`.
- AC3: Given `fn :: add Int Int => Int`, `fold add 0 [1, 2, 3, 4]` evaluates to `10`.
