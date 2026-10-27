---
id: FR-COMP-014
title: Idiomatic Pipeline Chaining (->), Left-Operand Operator/Function Invocation, and Direct Side-Effect Statements
status: implemented
priority: must
created: 2026-10-27
updated: 2026-10-27
depends_on:
  - FR-COMP-001
  - FR-COMP-003
  - FR-COMP-005
  - FR-COMP-008
  - FR-COMP-009
  - FR-COMP-013
verified_by: []
---
# FR-COMP-014 — Idiomatic Pipeline Chaining (`->`), Left-Operand Operator/Function Invocation, and Direct Side-Effect Statements

## Statement
The Ridgun language and `ridgunc` compiler SHALL provide left-to-right operator/function pipeline chaining (`->`), left-operand invocation (`xs map f`), sequence mask filtering (`-> (+ _ _ +) ->`), explicit unit discarding (`-> ()`), and direct side-effect statements without requiring `_ =`:

1. **Left-Operand Infix Invocation (`xs map f`, `st op args`)**:
   - Any function or operator `f` of arity $N \ge 2$ MAY be invoked with its first argument placed on the left (`x f a_2 ... a_N`), equivalent to `x -> f a_2 ... a_N` and `f x a_2 ... a_N`.
   - For the collection combinators (`map`, `||map`, `filter`, `||filter`, `fold`), both the prefix form (`map f xs`, `filter g xs`, `fold f init xs`) and the left-operand / pipeline form (`xs map f`, `xs -> map f`, `xs filter g`, `xs -> filter g`, `xs fold init f` / `xs -> fold f init`) SHALL be accepted and normalized to the same call.

2. **`->` Pipeline Stage Chaining (`E1 -> stage2 -> stage3`)**:
   - In an expression `left_e -> rhs_e` (including multi-line pipelines where indented continuation lines begin with `->`), the result of `left_e` SHALL be passed into `rhs_e` as its leading input:
     - **Collection combinators (`-> map f`, `-> ||map f`, `-> filter g`, `-> ||filter g`, `-> fold f init`)**: `left_e` supplies the collection argument.
     - **Agent message passing (`-> send to ag`, `-> ask to ag`)**: `left_e` supplies the message sent to agent `ag` (`send left_e to ag`, `ask left_e to ag`).
     - **Sequence mask filtering (`-> (+ _ _ +)`)**: applies `ESeqSelect left_e mask` (`left_e(+ _ _ +)`) to filter/select tuple elements in transit along the pipeline, verifying at compile time that the mask length matches the tuple arity and preserving the exact types of the selected elements.
     - **Explicit unit discard (`-> ()`)**: evaluates `left_e`, discards its value, and yields `()` (`TyUnit`).
     - **Explicit placeholder (`-> fn a _ c`)**: if `rhs_e` contains `_`, `left_e` replaces `_`.
     - **General `op ::` and `fn ::` calls (`-> fn a b` or `-> fn_1_arg`)**: `left_e` is passed as the **first argument** (`fn left_e a b` or `fn_1_arg left_e`), or matched against any declared mixfix `op ::` starting with `[left_e, fn, a, b]`.

3. **Terminal `-> var` Variable Binding in Sequential and Parallel Blocks**:
   - When a pipeline statement in a sequential block ends with `-> var_name` where `var_name` is not a declared function/operator taking arguments (`xs map f -> filter g -> results`), `ridgunc` SHALL bind the result of the pipeline to the immutable local variable `var_name` (`StmtLet var_name <pipeline>`), managed identically by `RMM1`/`RMM2`.
   - Inside a `||` parallel DAG line (`|| xs map f -> filter g -> results`), intermediate `->` stages SHALL be evaluated within the branch expression while the terminal `-> results` binds the DAG output variable `results`.

4. **Direct Side-Effect Statements Without `_ =`**:
   - Statements in sequential blocks (`echo`, `write file`, `shell exec`, `print error lines`, `sys exit`, `send ... to`, etc.) SHALL NOT require `_ =` before the expression. Non-final expression statements automatically discard their return value (`NDropVal`) and release dead temporaries via `RMM1`/`RMM2`; if the final statement of a `=> ()` function returns a non-unit value, `-> ()` (or automatic `=> ()` return discarding) yields `()`.

## Rationale
Chaining transformations from left to right (`xs map f -> filter g -> send to my_agent -> result`) matches the natural temporal order of dataflow without object-oriented method attachment or nested parentheses, while eliminating `st1`/`st2`/`st3` state-threading boilerplate and `_ =` visual noise.

## Acceptance Criteria
- **AC-1**: `xs map f -> filter g -> results` and `xs -> map f -> filter g -> results` and `map f xs -> filter g -> results` all compile to the same AST and produce identical results.
- **AC-2**: Multi-line pipelines where continuation lines begin with `->`, agent pipelines (`-> send to ag`), sequence mask stages (`-> (+ _ _ +) ->`), and unit discard stages (`-> ()`) compile and pass typechecking and execution tests.
- **AC-3**: Side-effect statements without `_ =` compile and execute cleanly without memory leaks under `RMM1`/`RMM2`.
