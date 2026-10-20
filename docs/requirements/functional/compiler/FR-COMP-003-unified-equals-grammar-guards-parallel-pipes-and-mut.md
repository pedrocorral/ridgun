---
id: FR-COMP-003
title: Unified `=` Block Grammar (`(none)`, `|`, `||` without `where`) and Explicit `mut` Variable Bindings
status: implemented
priority: must
created: 2026-10-20
updated: 2026-10-20
depends_on:
  - FR-COMP-002
verified_by: []
---
# FR-COMP-003 — Unified `=` Block Grammar (`(none)`, `|`, `||` without `where`) and Explicit `mut` Variable Bindings

## Statement
The Ridgun language and `ridgunc` compiler SHALL unify block, conditional, parallel, and variable-binding syntax under four rules:
1. **Universal `=` Right-Hand Side (`(none)` / `|` / `||`)**: Every function clause (`fn ::`), operator clause (`op ::`), local variable binding (`x =` / `mut x =`), and guard branch (`| cond =` / `| otherwise =`) SHALL require `=` and SHALL accept any of the following right-hand-side forms:
   - Inline expression (optionally followed on subsequent lines by `|| expr -> var` parallel bindings),
   - Sequential block (indented lines with no prefix),
   - Conditional guard block (`| cond = ...` and `| otherwise = ...`),
   - Parallel DAG block (`|| expr -> var` or `|| expr`).
2. **Guard Blocks (`|`) Behind `=` & Nested Block Closers (`|.` / `||.`)**:
   - Guarded function and operator clauses SHALL include `=` after their pattern list (`name pats =` followed by `| cond = ...`).
   - Local variable bindings SHALL support conditional guard blocks (`x =` followed by `| cond = ...`).
   - Guard branches (`| cond =` and `| otherwise =`) SHALL support nested `|` guard blocks to form arbitrary decision trees (3–4+ levels deep).
   - When a nested `|` or `||` block finishes and execution continues at an outer/parent level below it, the nested block MAY be explicitly closed with **`|.`** (for `|`) or **`||.`** (for `||`), either **inline at the end of the last line** (`| otherwise = expr |.`, the canonical compact form) or on the following line (`|.`). At the end of a function or outer block where no ambiguity exists, `|.` and `||.` are omitted.
3. **Elimination of `where` in Favor of `||`**:
   - The `where` keyword SHALL be removed from the language grammar.
   - Named parallel sub-computations feeding an expression SHALL be written directly as `|| expr -> var` (or `|| expr -> target[i, j]`) beneath the expression.
4. **Immutable-by-Default (`x = ...`), Explicit Mutable Variables (`mut x = ...`), and Lowercase Logical Operators (`and`, `or`, `xor`, `not`)**:
   - A binding `x = expr` without `mut` SHALL declare an immutable local variable; reassigning an immutable variable in the same scope SHALL be rejected at compile time, unless `x` was previously declared with `mut x = expr` in that scope.
   - Reassigning a `mut` variable (`x = new_expr`) SHALL integrate with `RMM2` (`FR-COMP-002`) by incrementing (`+1`) the new structure before decrementing (`-1`, and destroying on `0` with child cascade) the previous structure held by `x`.
   - Word-based logical operators SHALL be lowercase (`and`, `or`, `xor`, `not`), while also remaining usable as contextual words inside natural-language operator declarations (`op ::`).

## Rationale
- Placing `|` behind `=` eliminates the only syntactic exception where function clauses omitted `=`, aligns `=` vertically under `=>` across 100% of declarations, enables inline conditional variable assignments (`x =` followed by `|`), and allows recursive decision trees (`| otherwise =` followed by nested `|`).
- Replacing `where` with `|| expr -> var` removes a redundant keyword and unifies Ridgun's block prefixes into a clean triad: **nothing** (sequential), **`|`** (conditional OR choice), and **`||`** (parallel AND execution).
- Immutable-by-default (`x = ...`) keeps mathematical expressions clean while `mut x = ...` (at declaration, followed by `x = ...` on update) makes mutability explicit to both human readers and the `RMM2` memory manager.

## Functional Specification

### 1. Case 1 — Guarded Function & Operator Clauses (`=` Before `|`)
```ridgun
op :: clamp Int between Int and Int => Int
      clamp x   between lo  and hi  =
        | x < lo    = lo
        | x > hi    = hi
        | otherwise = x
```

### 2. Case 2 — Conditional Local Variable Assignment (`x =` Followed by `|`)
```ridgun
fn :: compute_invoice Int Bool => Int
      compute_invoice base is_vip =
        discount =
          | is_vip    = 20
          | base > 50 = 10
          | otherwise = 0
        base - discount
```

### 3. Case 3 — Deeply Nested Decision Trees (`|` Inside `| cond =` / `| otherwise =`) & Compact `|.` / `||.` Closers
When a nested `|` or `||` sub-tree finishes and the outer level continues below it, **`|.`** (or **`||.`**) closes the inner block and returns to the parent level. Both inline placement at the end of the last branch (`| otherwise = val |.`, canonical compact style) and next-line placement (`|.`) are valid; at the final branch of a function, no closer is needed:

```ridgun
fn :: evaluate_payment Account Customer Payment => String
      evaluate_payment account customer payment =
        | is_locked account   = "REJECTED_ACCOUNT_LOCKED"
        | amount payment <= 0 = "ERROR_INVALID_AMOUNT"
        | otherwise =
            | tier customer == "ENTERPRISE" =
                | amount payment > 50000 =
                    | has_dual_signature payment = "APPROVED_ENTERPRISE_DUAL_SIG"
                    | tenure customer > 10       = "RISK_COMMITTEE_REVIEW"
                    | otherwise                  = "REJECTED_ENTERPRISE_LIMIT" |.
                | country payment != "US" =
                    | is_whitelisted (country payment) = "APPROVED_ENTERPRISE_INTL"
                    | otherwise                        = "HELD_COMPLIANCE_INTL" |.
                | otherwise = "APPROVED_ENTERPRISE_STANDARD" |.
            | tier customer == "VIP" =
                | amount payment > 10000 =
                    | has_2fa payment = "APPROVED_VIP_2FA"
                    | otherwise       = "REQUEST_VIP_SMS" |.
                | otherwise = "APPROVED_VIP_DIRECT" |.
            | otherwise =
                | amount payment > 1000 =
                    | has_2fa payment and risk payment < 30 = "APPROVED_RETAIL_2FA"
                    | otherwise                             = "REJECTED_RETAIL_RISK" |.
                | otherwise = "APPROVED_RETAIL_LOW_AMOUNT"
```

Similarly, when a parallel `||` block or a conditional `|` assignment sits in the middle of a sequential block and execution continues with subsequent statements, `||.` / `|.` marks the return to the sequential level:

```ridgun
fn :: charge_order Payment => Int
      charge_order payment =
        || fetch_base_fee payment   -> base_fee
        || compute_risk_score payment -> risk_score ||.
        surcharge =
          | risk_score > 80 = 50
          | otherwise       = 0 |.
        base_fee + surcharge
```

### 4. Case 4 — Parallel `||` DAG Blocks (Replacing `where`)
- **Named parallel DAG feeding a header expression (`|| expr -> var`)**:
  ```ridgun
  fn :: parallel_dag_calc => Int
        parallel_dag_calc =  a + b
          || fib 10       -> a
          || fact 6       -> b
  ```
- **Anonymous parallel tuple branches (`|| expr`)**:
  ```ridgun
  fn :: both_metrics Int => (Int, Int)
        both_metrics x   =
          || fib x
          || fact x
  ```
- **Indexed parallel slot assignment (`|| expr -> target[i, j]`)**:
  ```ridgun
  fn :: fill_row => Tensor
        fill_row =  m
          || 10.0 -> m[0, 0]
          || 20.0 -> m[0, 1]
  ```

### 5. Case 5 — Immutable (`x = ...`) vs Mutable (`mut x = ...`) Variables & `RMM2` Lifecycle
- **Immutable binding (`x = expr`)**:
  - `x` is bound once (`+1` on structure assignment). Any subsequent `x = ...` in the same scope without a prior `mut x = ...` raises a compile-time error (`ErrImmutableReassign`).
- **Mutable declaration & reassignment (`mut x = expr`, then `x = new_expr`)**:
  - First declaration `mut x = e1`: marks `x` as mutable in the current scope and assigns `e1` (`+1`).
  - Subsequent update `x = e2`:
    1. Evaluates `e2` and increments its reference count (`+1`).
    2. Decrements (`-1`) the old value stored in `x` (destroying it and cascading `-1` to its children if its count reaches `0`).
    3. Stores `e2` into `x`.
    *(Incrementing `e2` before decrementing the old `x` guarantees safety on self-referential updates such as `x = choose_list cond x other` or `x = x[0]`).*

## Acceptance Criteria
- AC1: `=` precedes `|` in function/operator clauses, local variable bindings, and nested `|` decision trees.
- AC2: `|| expr -> var` replaces `where` for parallel DAG bindings, and `where` is no longer a reserved keyword.
- AC3: `mut x = ...` enables subsequent `x = ...` reassignments in the same scope under `RMM2`, while reassigning a non-`mut` variable fails typechecking.
